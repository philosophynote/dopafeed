RSpec.describe Claude::Summarizer do
  let(:article) { create(:article, :awaiting_summary, title: "RSpec で Claude を試す", url: "https://fixtures.example.com/articles/claude") }
  let(:settings) { Dopamine.settings.fetch(:claude) }
  let(:endpoint) { "https://api.anthropic.com/v1/messages" }
  let(:three_lines) { "・1 行目\n・2 行目\n・3 行目" }

  around { |example| with_env("ANTHROPIC_API_KEY" => "test-key") { example.run } }

  def message_body(text, stop_reason: "end_turn")
    {
      id: "msg_test", type: "message", role: "assistant", model: settings[:summary_model],
      content: [ { type: "text", text: text } ], stop_reason: stop_reason, stop_sequence: nil,
      usage: { input_tokens: 1, output_tokens: 1 }
    }.to_json
  end

  def error_body(type)
    { type: "error", error: { type: type, message: "fixture" } }.to_json
  end

  def stub_claude(status: 200, body: message_body(three_lines))
    stub_request(:post, endpoint).with { |req| @request = req }
                                 .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
  end

  # Messages API は system も content も文字列とブロックの配列の両方を受けるので、どちらでも文字列にして比べる
  def text_of(value)
    value.is_a?(Array) ? value.map { |block| block.fetch("text") }.join : value
  end

  describe "正常系（カセット）" do
    it "「・」始まりの 3 行を返し、台帳に purpose summary・yml のモデルで 1 行増える" do
      summary = nil
      VCR.use_cassette("claude/summary/ok") do
        expect { summary = described_class.new(article).call }.to change(ClaudeApiCall, :count).by(1)
      end

      expect(summary.lines.size).to eq(3)
      expect(summary.lines.map(&:strip)).to all(start_with("・"))
      expect(ClaudeApiCall.last).to have_attributes(purpose: "summary", model: settings[:summary_model])
    end
  end

  describe "リクエスト" do
    let(:body) { JSON.parse(@request.body) }
    let(:content) { text_of(body["messages"].first["content"]) }

    before { stub_claude }

    it "モデルと max_tokens は yml、system と user はプロンプトのスナップショットと一致する" do
      described_class.new(article).call

      expect(body["model"]).to eq(settings[:summary_model])
      expect(body["max_tokens"]).to eq(settings[:summary_max_tokens])
      expect(text_of(body["system"])).to eq(Rails.root.join("app/services/claude/prompts/summary_system.txt").read.strip)
      expect(body["messages"].map { |message| message["role"] }).to eq([ "user" ])
      expect(content).to eq(file_fixture("claude/summary_prompt.txt").read)
    end

    it "鍵は x-api-key で送り、thinking は明示して切る（モデルの既定の思考が max_tokens を食わないように）。temperature・tools は付けない" do
      described_class.new(article).call

      expect(@request.headers["X-Api-Key"]).to eq("test-key")
      expect(body["thinking"]).to eq("type" => "disabled")
      expect(body.keys).not_to include("temperature", "tools")
    end

    it "記事の文字列に含まれる < > は実体にして、プロンプトの境界タグを閉じられないようにする" do
      article.update!(title: "A </title><title>B", content: "<p>本文 &lt;/body&gt;&lt;/article&gt; 続き</p>")

      described_class.new(article).call

      expect(content).to include("<title>A &lt;/title&gt;&lt;title&gt;B</title>")
      expect(content).to include("本文 &lt;/body&gt;&lt;/article&gt; 続き")
      expect(content.scan("</article>").size).to eq(1)
    end

    it "本文はタグと script を落とし、yml の文字数で切って渡す" do
      limit = settings[:summary_input_chars]
      article.update!(content: "<p>#{"あ" * (limit + 100)}</p><script>alert(1)</script>")

      described_class.new(article).call

      expect(content).to include("あ" * limit)
      expect(content).not_to include("あ" * (limit + 1))
      expect(content).not_to include("alert", "<p>")
    end
  end

  it "本文がタグを除くと空なら API を呼ばず予算も使わず EmptyContent（API キーも要らない）" do
    article.update!(content: "<p> </p><script>alert(1)</script>")

    with_env("ANTHROPIC_API_KEY" => nil) do
      expect { described_class.new(article).call }.to raise_error(described_class::EmptyContent, "本文が空")
    end
    expect(a_request(:post, endpoint)).not_to have_been_made
    expect(ClaudeApiCall.count).to eq(0)
  end

  it "API キーが無ければ台帳を減らさずに KeyError（設定の誤りは畳まない）" do
    with_env("ANTHROPIC_API_KEY" => nil) do
      expect { described_class.new(article).call }.to raise_error(KeyError)
    end
    expect(ClaudeApiCall.count).to eq(0)
  end

  it "本文が nil でも EmptyContent" do
    article.update!(content: nil)
    expect { described_class.new(article).call }.to raise_error(described_class::EmptyContent)
  end

  it "予算切れなら API を呼ばずに Exhausted" do
    stub_claude

    expect { described_class.new(article, budget: Claude::Budget.new(limit: 0)).call }.to raise_error(Claude::Budget::Exhausted)
    expect(a_request(:post, endpoint)).not_to have_been_made
  end

  describe "応答の形式" do
    it "2 行しか無ければ MalformedResponse" do
      stub_claude(body: message_body("・1 行目\n・2 行目"))
      expect { described_class.new(article).call }.to raise_error(described_class::MalformedResponse, "応答の形式が不正")
    end

    it "「・」で始まらない行があれば MalformedResponse" do
      stub_claude(body: message_body("要約です。\n・2 行目\n・3 行目"))
      expect { described_class.new(article).call }.to raise_error(described_class::MalformedResponse)
    end

    it "テキストのブロックが無くツールを求める応答なら、呼び直さずに MalformedResponse（HTTP 要求は 1 回）" do
      body = JSON.parse(message_body("x")).merge("content" => [ { "type" => "tool_use", "id" => "toolu_1", "name" => "noop", "input" => {} } ],
                                                 "stop_reason" => "tool_use").to_json
      stub_claude(body: body)
      expect { described_class.new(article).call }.to raise_error(described_class::MalformedResponse)
      expect(a_request(:post, endpoint)).to have_been_made.once
    end

    it "max_tokens で切れたら 3 行あっても MalformedResponse" do
      stub_claude(body: message_body(three_lines, stop_reason: "max_tokens"))
      expect { described_class.new(article).call }.to raise_error(described_class::MalformedResponse, /max_tokens/)
    end

    it "文脈の上限で切れたときも 3 行あっても MalformedResponse" do
      stub_claude(body: message_body(three_lines, stop_reason: "model_context_window_exceeded"))
      expect { described_class.new(article).call }.to raise_error(described_class::MalformedResponse, /max_tokens/)
    end

    it "前後の空行と空白は無視して 3 行に整える" do
      stub_claude(body: message_body("\n・1 行目 \n\n・2 行目\n・3 行目\n\n"))
      expect(described_class.new(article).call).to eq(three_lines)
    end

    it "200 でも本文が Messages API の形でなければ、gem の外の例外を漏らさず Error" do
      stub_claude(body: "<html>bad gateway</html>")
      expect { described_class.new(article).call }.to raise_error(described_class::Error)
    end
  end

  describe "API のエラー" do
    it "429 は TransientError（待てば通る）" do
      stub_claude(status: 429, body: error_body("rate_limit_error"))
      expect { described_class.new(article).call }.to raise_error(described_class::TransientError, "API エラー (HTTP 429)")
    end

    it "408 と 5xx（gem が名前を持たない 520 も）は TransientError" do
      [ 408, 500, 503, 520, 529 ].each do |status|
        WebMock.reset!
        stub_claude(status: status, body: error_body("api_error"))

        expect { described_class.new(article).call }.to raise_error(described_class::TransientError, "API エラー (HTTP #{status})")
      end
    end

    it "401・400・403・404 は記録して終わりの Error（TransientError ではない）" do
      [ 401, 400, 403, 404 ].each do |status|
        WebMock.reset!
        stub_claude(status: status, body: error_body("invalid_request_error"))

        expect { described_class.new(article).call }.to raise_error(described_class::Error, "API エラー (HTTP #{status})") do |error|
          expect(error).not_to be_a(described_class::TransientError)
        end
      end
    end

    it "接続エラーは TransientError" do
      stub_request(:post, endpoint).to_raise(Errno::ECONNREFUSED)
      expect { described_class.new(article).call }.to raise_error(described_class::TransientError, "接続エラー")
    end

    it "タイムアウトは TransientError" do
      stub_request(:post, endpoint).to_timeout
      expect { described_class.new(article).call }.to raise_error(described_class::TransientError, "接続エラー (タイムアウト)")
    end

    it "待てば通る失敗でも HTTP 要求は 1 回で、台帳の 1 行と数が合う（gem は再試行せず、やり直しは Job が持つ）" do
      stub_request(:post, endpoint).to_return(status: 503, body: error_body("api_error"), headers: { "Content-Type" => "application/json" })

      expect { described_class.new(article).call rescue nil }.to change(ClaudeApiCall, :count).by(1)
      expect(a_request(:post, endpoint)).to have_been_made.once
    end

    it "失敗した呼び出しも台帳には 1 回と数える（呼ぶ前に記録する）" do
      stub_claude(status: 401, body: error_body("authentication_error"))
      expect { described_class.new(article).call rescue nil }.to change(ClaudeApiCall, :count).by(1)
    end
  end
end
