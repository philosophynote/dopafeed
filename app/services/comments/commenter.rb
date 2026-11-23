module Comments
  # 全員分を 1 本の応答で書かせると、書き終えるまで誰のコメントも出せないため、1 人分ずつ作る。
  class Commenter
    class Error < StandardError; end
    class EmptyContent < Error; end
    class MalformedResponse < Error; end
    class TransientError < Error; end

    PURPOSE = "comments".freeze
    TRANSIENT_STATUSES = [ 408, 429 ].freeze
    # 思考の間は 1 文字も流れてこず、感想の口調は思考なしでも保てるので、思考させない。
    THINKING_EFFORT = :none
    PROMPTS = Rails.root.join("app/services/comments/prompts")

    def initialize(article, persona, budget: Claude::Budget.new, client: nil)
      @article = article
      @persona = persona
      @budget = budget
      @client = client
    end

    # 常にストリーミングで受ける。ブロックを渡すと、書けた分を頭から積み上げた文字列で yml の間隔ごとに渡す
    def call(&on_text)
      text = article.plain_content.first(input_chars)
      raise EmptyContent, "本文が空" if text.blank?

      # 設定の欠けで台帳だけ減っていかないよう、鍵と yml の値は記録の前にすべて読む
      client
      model = settings.fetch(:model)
      max_tokens = settings.fetch(:max_tokens)
      interval_ms = settings.fetch(:stream_interval_ms)
      budget.record!(purpose: PURPOSE, model: model)
      parse(request(text, model:, max_tokens:, interval_ms:, &on_text))
    end

    private

    attr_reader :article, :persona, :budget

    def client
      @client ||= Client.build
    end

    # ask はツールを求める応答に答えて呼び直し続け、台帳の 1 行を超えて払うので、1 回だけ生成する generate を使う。
    def request(text, model:, max_tokens:, interval_ms:, &on_text)
      chat = client.chat(model: model, provider: Client::PROVIDER, assume_model_exists: true)
                   .with_instructions(system_prompt)
                   .with_max_output_tokens(max_tokens)
                   .with_thinking(effort: THINKING_EFFORT)
                   .ask_later(user_prompt(text))
      stream(chat, interval_ms, &on_text)
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

    # 断片ごとに配ると、配るたびに Solid Cable が SQLite へ 1 行書くので、間隔ごとにまとめる
    def stream(chat, interval_ms)
      written = +""
      sent_at = monotonic_ms
      chat.generate do |chunk|
        next unless block_given? && chunk.content.is_a?(String) && !chunk.content.empty?

        written << chunk.content
        next if monotonic_ms - sent_at < interval_ms

        sent_at = monotonic_ms
        yield written.strip
      end
    end

    def monotonic_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    end

    # 終わりの知らせが無いまま閉じた流れや、上限で切れた文は途中で終わっているので、本文があっても残さない
    def parse(message)
      raise TransientError, "接続エラー (途中で切れた)" if message.finish_reason.nil?
      raise MalformedResponse, "応答の形式が不正 (max_tokens で切れた)" if message.finish_reason == :max_tokens
      raise MalformedResponse, "応答の形式が不正 (#{message.finish_reason})" unless message.finish_reason == :stop

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
