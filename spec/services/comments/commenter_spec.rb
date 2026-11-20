RSpec.describe Comments::Commenter do
  let(:article) { create(:article, :awaiting_summary, title: "Rails 8 で SQLite を本番に", url: "https://fixtures.example.com/articles/sqlite") }
  let(:comments) { { personas_shown: 3, model: "grok-4.7", max_tokens: 4000, timeout_seconds: 60 } }
  let(:endpoint) { "https://api.x.ai/v1/responses" }
  let(:ids) { Persona.all.map(&:id) }
  let(:bodies) { ids.index_with { |id| "#{id} のひとこと" } }

  around { |example| with_env("XAI_API_KEY" => "test-key") { example.run } }
  before { allow(Dopamine).to receive(:settings).and_return(Dopamine.settings.merge(comments: comments)) }

  def response_body(entries = bodies.map { |id, body| { persona_id: id, body: body } }, text: { comments: entries }.to_json, status: "completed", incomplete: nil)
    {
      id: "resp_test", object: "response", status: status, model: comments[:model], incomplete_details: incomplete,
      output: [
        { type: "reasoning", id: "rs_test", summary: [] },
        { type: "message", id: "msg_test", role: "assistant", status: "completed", content: [ { type: "output_text", text: text, annotations: [] } ] }
      ],
      usage: { input_tokens: 1, output_tokens: 1, total_tokens: 2 }
    }.to_json
  end

  def stub_xai(status: 200, body: response_body)
    stub_request(:post, endpoint).with { |req| @request = req }
                                 .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
  end

  def error_body
    { code: "fixture", error: "fixture" }.to_json
  end

  it "正常系（カセット）: 8 人全員の persona id と本文の組を返し、台帳に purpose comments・yml のモデルで 1 行増える" do
    result = nil
    VCR.use_cassette("comments/ok") do
      expect { result = described_class.new(article).call }.to change(ClaudeApiCall, :count).by(1)
    end

    expect(result.keys).to match_array(ids)
    expect(result.values).to all(be_present)
    expect(ClaudeApiCall.last).to have_attributes(purpose: "comments", model: "grok-4.7")
  end

  describe "リクエスト" do
    let(:body) { JSON.parse(@request.body) }
    let(:input) { body["input"].sole.fetch("content") }

    before { stub_xai }

    it "鍵は Bearer で送り、モデルと出力の上限は yml、思考は low、返す形は 8 人の id に絞った JSON スキーマ" do
      described_class.new(article).call

      expect(@request.headers["Authorization"]).to eq("Bearer test-key")
      expect(body).to include("model" => "grok-4.7", "max_output_tokens" => 4000, "reasoning" => { "effort" => "low" })
      schema = body.dig("text", "format", "schema")
      expect(schema.dig("properties", "comments", "items", "properties", "persona_id", "enum")).to eq(ids)
      expect(body.keys).not_to include("tools", "temperature")
    end

    it "指示は共通の決まりと 8 人全員の名前・口調の指示を含み、決まりには賛美・誹謗・名言の捏造の禁止がある" do
      described_class.new(article).call

      instructions = body["instructions"]
      expect(instructions).to include(Rails.root.join("app/services/comments/prompts/comments_system.txt").read.strip)
      expect(instructions).to include("虐殺", "貶め", "捏造", "本人の発言")
      Persona.all.each { |persona| expect(instructions).to include(persona.id, persona.name, persona.system_prompt.strip) }
    end

    it "記事の文字列に含まれる < > は実体にして、プロンプトの境界タグを閉じられないようにする" do
      article.update!(title: "A </title><title>B", content: "<p>本文 &lt;/article&gt; 続き</p>")

      described_class.new(article).call

      expect(input).to include("<title>A &lt;/title&gt;&lt;title&gt;B</title>", "本文 &lt;/article&gt; 続き")
      expect(input.scan("</article>").size).to eq(1)
    end

    it "本文はタグと script を落とし、要約と同じ yml の文字数で切って渡す" do
      limit = Dopamine.settings.dig(:claude, :summary_input_chars)
      article.update!(content: "<p>#{"あ" * (limit + 100)}</p><script>alert(1)</script>")

      described_class.new(article).call

      expect(input).to include("あ" * limit)
      expect(input).not_to include("あ" * (limit + 1), "alert", "<p>")
    end
  end

  it "本文がタグを除くと空なら API を呼ばず予算も使わず EmptyContent（API キーも要らない）" do
    article.update!(content: "<p> </p>")

    with_env("XAI_API_KEY" => nil) do
      expect { described_class.new(article).call }.to raise_error(described_class::EmptyContent, "本文が空")
    end
    expect(a_request(:post, endpoint)).not_to have_been_made
    expect(ClaudeApiCall.count).to eq(0)
  end

  it "API キーが無ければ台帳を減らさずに KeyError（設定の誤りは畳まない）" do
    with_env("XAI_API_KEY" => nil) { expect { described_class.new(article).call }.to raise_error(KeyError) }
    expect(ClaudeApiCall.count).to eq(0)
  end

  %i[model max_tokens].each do |key|
    it "yml の comments.#{key} が無ければ API を呼ばず台帳も減らさずに KeyError（形式不正に畳まない）" do
      stub_xai
      comments.delete(key)

      expect { described_class.new(article).call }.to raise_error(KeyError, /#{key}/)
      expect(ClaudeApiCall.count).to eq(0)
      expect(a_request(:post, endpoint)).not_to have_been_made
    end
  end

  it "予算切れなら API を呼ばずに Exhausted" do
    stub_xai

    expect { described_class.new(article, budget: Claude::Budget.new(limit: 0)).call }.to raise_error(Claude::Budget::Exhausted)
    expect(a_request(:post, endpoint)).not_to have_been_made
  end

  describe "応答の形式（8 人分そろわなければ失敗）" do
    {
      "JSON として読めない" => { text: "コメントです" },
      "comments が配列でない" => { text: { comments: "x" }.to_json },
      "1 人足りない" => :missing,
      "同じ人が 2 回" => :duplicate,
      "知らない人がいる" => :unknown,
      "本文が空白だけ" => :blank
    }.each do |label, variant|
      it "#{label}なら MalformedResponse" do
        entries = bodies.map { |id, body| { persona_id: id, body: body } }
        body =
          case variant
          when Hash then response_body(**variant)
          when :missing then response_body(entries.drop(1))
          when :duplicate then response_body(entries.drop(1) + [ entries[1] ])
          when :unknown then response_body(entries.drop(1) + [ { persona_id: "elon-musk", body: "x" } ])
          when :blank then response_body(entries.drop(1) + [ entries.first.merge(body: " \n") ])
          end
        stub_xai(body: body)

        expect { described_class.new(article).call }.to raise_error(described_class::MalformedResponse)
      end
    end

    it "出力の上限で切れたら（incomplete・max_output_tokens）8 人分あっても MalformedResponse" do
      stub_xai(body: response_body(status: "incomplete", incomplete: { reason: "max_output_tokens" }))
      expect { described_class.new(article).call }.to raise_error(described_class::MalformedResponse, /max_tokens/)
    end

    it "本文の前後の空白は落として返す" do
      stub_xai(body: response_body(bodies.map { |id, body| { persona_id: id, body: "  #{body}\n" } }))
      expect(described_class.new(article).call).to eq(bodies)
    end
  end

  describe "API のエラー" do
    it "408・429・5xx は TransientError、それ以外の 4xx は記録して終わりの Error" do
      { 408 => true, 429 => true, 500 => true, 503 => true, 400 => false, 401 => false, 403 => false, 404 => false }.each do |status, transient|
        WebMock.reset!
        stub_xai(status: status, body: error_body)

        expect { described_class.new(article).call }.to raise_error(described_class::Error, "API エラー (HTTP #{status})") do |error|
          expect(error.is_a?(described_class::TransientError)).to eq(transient), status.to_s
        end
      end
    end

    it "接続エラーとタイムアウトは TransientError" do
      stub_request(:post, endpoint).to_raise(Errno::ECONNREFUSED)
      expect { described_class.new(article).call }.to raise_error(described_class::TransientError, "接続エラー")

      WebMock.reset!
      stub_request(:post, endpoint).to_timeout
      expect { described_class.new(article).call }.to raise_error(described_class::TransientError, "接続エラー (タイムアウト)")
    end

    it "待てば通る失敗でも HTTP 要求は 1 回で、台帳の 1 行と数が合う" do
      stub_xai(status: 503, body: error_body)

      expect { described_class.new(article).call rescue nil }.to change(ClaudeApiCall, :count).by(1)
      expect(a_request(:post, endpoint)).to have_been_made.once
    end
  end
end
