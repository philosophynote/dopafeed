module Comments
  # 全員分を 1 本の応答で書かせると、書き終えるまで誰のコメントも出せないため、1 人分ずつ作る。
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

    def initialize(article, persona, budget: Claude::Budget.new, client: nil)
      @article = article
      @persona = persona
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

    attr_reader :article, :persona, :budget

    def client
      @client ||= Client.build
    end

    # ask はツールを求める応答に答えて呼び直し続け、台帳の 1 行を超えて払うので、1 回だけ生成する generate を使う。
    def request(text, model:, max_tokens:)
      client.chat(model: model, provider: Client::PROVIDER, assume_model_exists: true)
            .with_instructions(system_prompt)
            .with_max_output_tokens(max_tokens)
            .with_thinking(effort: THINKING_EFFORT)
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

    # 上限で切れた文は途中で終わっているので、本文があっても残さない
    def parse(message)
      raise MalformedResponse, "応答の形式が不正 (max_tokens で切れた)" if message.finish_reason == :max_tokens

      body = message.content.to_s.strip
      raise MalformedResponse, "応答の形式が不正" if body.blank?

      body
    end

    def system_prompt
      [ PROMPTS.join("comments_system.txt").read.strip, "#{persona.name}（#{persona.title}）\n#{persona.system_prompt.strip}" ].join("\n\n")
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
