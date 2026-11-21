module Comments
  # 組を替えるたびに払わないよう、1 回で全員分を作る。1 人でも欠けた応答は返さず失敗にする。
  class Commenter
    class Error < StandardError; end
    class EmptyContent < Error; end
    class MalformedResponse < Error; end
    class TransientError < Error; end

    PURPOSE = "comments".freeze
    TRANSIENT_STATUSES = [ 408, 429 ].freeze
    # ひとことに深い思考は要らず、思考のトークンも出力の上限に数えられるので、一番浅くする。
    THINKING_EFFORT = :low
    PROMPTS = Rails.root.join("app/services/comments/prompts")

    def initialize(article, personas: Persona.all, budget: Claude::Budget.new, client: nil)
      @article = article
      @personas = personas
      @budget = budget
      @client = client
    end

    def call
      text = article.plain_content.first(input_chars)
      raise EmptyContent, "本文が空" if text.blank?

      # 設定の欠けで台帳だけ減っていかないよう、鍵と yml の値は記録の前にすべて読む
      client
      model = settings.fetch(:model)
      max_tokens = settings.fetch(:max_tokens)
      budget.record!(purpose: PURPOSE, model: model)
      parse(request(text, model:, max_tokens:))
    end

    private

    attr_reader :article, :personas, :budget

    def client
      @client ||= Client.build
    end

    # ask はツールを求める応答に答えて呼び直し続け、台帳の 1 行を超えて払うので、1 回だけ生成する generate を使う。
    def request(text, model:, max_tokens:)
      client.chat(model: model, provider: Client::PROVIDER, assume_model_exists: true)
            .with_instructions(system_prompt)
            .with_max_output_tokens(max_tokens)
            .with_thinking(effort: THINKING_EFFORT)
            .with_schema(schema)
            .ask_later(user_prompt(text))
            .generate
    rescue RubyLLM::Error => e
      raise classify(e)
    rescue StandardError => e
      raise Error, "応答の形式が不正 (#{e.class.name.demodulize})"
    end

    # 要約と同じ分け方。応答の文面は要求を引用しうるので、失敗の理由には状態だけを残す。
    def classify(error)
      status = error.response&.status
      return TransientError.new(error.try(:timeout?) ? "接続エラー (タイムアウト)" : "接続エラー") if status.nil?
      return Error.new("応答の形式が不正 (HTTP #{status})") if status < 400

      (status >= 500 || TRANSIENT_STATUSES.include?(status) ? TransientError : Error).new("API エラー (HTTP #{status})")
    end

    # スキーマを渡しても、守られなかった応答を保存して表示を崩さないよう、こちらでも確かめる。
    def parse(message)
      raise MalformedResponse, "応答の形式が不正 (max_tokens で切れた)" if message.finish_reason == :max_tokens

      entries = decode(message.content)
      bodies = entries.to_h { |entry| [ entry["persona_id"], entry["body"].to_s.strip ] }
      complete = entries.size == personas.size && bodies.keys.sort == personas.map(&:id).sort && bodies.values.all?(&:present?)
      raise MalformedResponse, "応答の形式が不正" unless complete

      bodies
    end

    def decode(content)
      data = content.is_a?(String) ? JSON.parse(content) : content
      entries = data.is_a?(Hash) && data["comments"]
      raise MalformedResponse, "応答の形式が不正" unless entries.is_a?(Array) && entries.all?(Hash)

      entries
    rescue JSON::ParserError
      raise MalformedResponse, "応答の形式が不正"
    end

    def schema
      {
        type: "object",
        properties: {
          comments: {
            type: "array",
            items: {
              type: "object",
              properties: { persona_id: { type: "string", enum: personas.map(&:id) }, body: { type: "string" } },
              required: %w[persona_id body],
              additionalProperties: false
            }
          }
        },
        required: %w[comments],
        additionalProperties: false
      }
    end

    def system_prompt
      sections = personas.map { |persona| "## #{persona.id}: #{persona.name}（#{persona.title}）\n#{persona.system_prompt.strip}" }
      [ PROMPTS.join("comments_system.txt").read.strip, *sections ].join("\n\n")
    end

    # 記事の文字列はタグで囲んで渡すので、中の < > を実体にして境界を偽装できなくする
    def user_prompt(text)
      ERB.new(PROMPTS.join("comments.erb").read, trim_mode: "-")
         .result_with_hash(title: escape(article.title), url: escape(article.url), content: escape(text))
    end

    def escape(string)
      string.to_s.gsub("<", "&lt;").gsub(">", "&gt;")
    end

    def settings
      Dopamine.settings.fetch(:comments)
    end

    def input_chars
      Dopamine.settings.dig(:claude, :summary_input_chars)
    end
  end
end
