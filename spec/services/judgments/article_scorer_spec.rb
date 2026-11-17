RSpec.describe Judgments::ArticleScorer do
  include_context "判定が設定済み"

  let(:article) { create(:article, :awaiting_summary, title: "RubyLLM で記事を採点する") }
  let(:scores) { { originality: 3.2, depth: 2.6, practicality: 3.0, evidence: 1.4, insight: 2.5, applicability: 0.4 } }

  def stub_judgment(status: 200, body: judgment_response(scores))
    stub_request(:post, JudgmentHelper::ENDPOINT).with { |req| @request = req }
                                                 .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
  end

  def payload
    JSON.parse(@request.body)
  end

  it "6 軸の小数の段・モデル・入力トークンを返し、台帳に 1 行増える（費用は応答に載らないので空）" do
    stub_judgment

    result = nil
    expect { result = described_class.new(article).call }.to change(ClaudeApiCall, :count).by(1)

    expect(result.scores).to eq(scores.stringify_keys)
    expect(result).to have_attributes(model: "jev-latest", input_tokens: 1200, cost: nil)
    expect(ClaudeApiCall.last).to have_attributes(purpose: "rarity_judgment", model: "jev-latest")
  end

  it "yml のモデルと API キーで、見出しとタグを落とした本文を 6 問まとめて 1 回送る" do
    stub_judgment

    described_class.new(article).call

    expect(@request.headers["Authorization"]).to eq("Bearer test-key")
    expect(payload).to include("model" => "jev-latest", "state" => { "title" => "RubyLLM で記事を採点する", "body" => "見出し\n最初の段落。\n二つ目の段落。" })
    expect(payload["questions"].keys).to eq(ArticleJudgment::AXES)
    expect(payload["questions"].values).to all(include("type" => "score"))
    expect(a_request(:post, JudgmentHelper::ENDPOINT)).to have_been_made.once
  end

  it "本文は yml の input_chars で切る" do
    stub_judgment
    article.update!(content: "<p>#{"あ" * 5000}</p>")

    described_class.new(article).call

    expect(payload.dig("state", "body").size).to eq(JudgmentHelper::SETTINGS[:input_chars])
  end

  it "本文が空なら API を呼ばず、台帳も増やさない" do
    article.update!(content: "<p> </p>")

    expect { expect { described_class.new(article).call }.to raise_error(described_class::EmptyContent) }.not_to change(ClaudeApiCall, :count)
    expect(a_request(:post, JudgmentHelper::ENDPOINT)).not_to have_been_made
  end

  it "予算切れなら API を呼ばない" do
    expect { described_class.new(article, budget: Claude::Budget.new(limit: 0)).call }.to raise_error(Claude::Budget::Exhausted)
    expect(a_request(:post, JudgmentHelper::ENDPOINT)).not_to have_been_made
  end

  it "API キーが無ければ、台帳を減らす前に KeyError で止まる" do
    with_env("TYPESAFE_API_KEY" => nil) do
      expect { expect { described_class.new(article).call }.to raise_error(KeyError) }.not_to change(ClaudeApiCall, :count)
    end
  end

  it "408・429 と 5xx（gem が名前を持たない 520 も）は時間を置けば通りうるので TransientError。gem の中では再試行しない（HTTP 要求は 1 回）" do
    [ 408, 429, 500, 503, 520, 529 ].each do |status|
      WebMock.reset!
      stub_judgment(status: status, body: { error: { message: "fixture" } }.to_json)

      expect { described_class.new(article).call }.to raise_error(described_class::TransientError, /HTTP #{status}/)
      expect(a_request(:post, JudgmentHelper::ENDPOINT)).to have_been_made.once
    end
  end

  it "タイムアウトも TransientError" do
    stub_request(:post, JudgmentHelper::ENDPOINT).to_timeout

    expect { described_class.new(article).call }.to raise_error(described_class::TransientError)
  end

  it "400 と 403（本文が内容の検査に掛かったときにも返る）は時間を置いても通らないので、記事の失敗の Error。応答の文面は載せない" do
    [ 400, 403 ].each do |status|
      WebMock.reset!
      stub_judgment(status: status, body: { error: { message: "secret-looking provider text" } }.to_json)

      expect { described_class.new(article).call }.to raise_error(described_class::Error) { |error|
        expect(error.class).to eq(described_class::Error)
        expect(error.message).to eq("API エラー (HTTP #{status})")
      }
    end
  end

  it "401・402 は鍵や残高の失敗で、記事の失敗と分ける（AccountError）" do
    [ 401, 402 ].each do |status|
      WebMock.reset!
      stub_judgment(status: status, body: { error: { message: "fixture" } }.to_json)

      expect { described_class.new(article).call }.to raise_error(described_class::AccountError, "API エラー (HTTP #{status})")
    end
  end

  it "軸の欠けた応答は Error" do
    stub_judgment(body: judgment_response(scores.except(:insight)))

    expect { described_class.new(article).call }.to raise_error(described_class::Error, "判定として読めない応答 (HTTP 200)")
  end

  it "gem が RubyLLM::Error 以外を上げても Error に包む（失敗を残せずに Job が死ぬと、開くたびに払い直す）" do
    allow(ArticleRarityJudge).to receive(:judge).and_raise(TypeError, "String can't be coerced into Float")

    expect { described_class.new(article).call }.to raise_error(described_class::Error, "応答の形式が不正 (TypeError)")
  end

  it "待ちは yml の judgment.timeout_seconds で、gem には再試行させない" do
    stub_judgment
    allow(ArticleRarityJudge).to receive(:judge).and_call_original

    described_class.new(article).call

    expect(ArticleRarityJudge).to have_received(:judge) do |_input, context:, **|
      expect(context.config).to have_attributes(request_timeout: JudgmentHelper::SETTINGS[:timeout_seconds], max_retries: 0)
    end
  end

  it "段の範囲を外れた点や数でない点の応答は Error" do
    [ 4.5, -1, nil, "3" ].each do |bad|
      WebMock.reset!
      stub_judgment(body: judgment_response(scores.merge(depth: bad)))

      expect { described_class.new(article).call }.to raise_error(described_class::Error, /応答の形式が不正/)
    end
  end

  describe ".configured?" do
    it "yml の judgment と API キーが揃っていれば真" do
      expect(described_class).to be_configured
    end

    it "API キーが無ければ偽" do
      with_env("TYPESAFE_API_KEY" => nil) { expect(described_class).not_to be_configured }
    end

    it "yml に judgment が無ければ偽" do
      allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.except(:judgment))

      expect(described_class).not_to be_configured
    end
  end
end
