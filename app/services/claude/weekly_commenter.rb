module Claude
  # 本文と URL は送らない。見出しだけで週の傾向は読め、入力の費用と外へ出す量を小さくできる。
  class WeeklyCommenter
    class Error < StandardError; end
    class MalformedResponse < Error; end
    class TransientError < Error; end

    PURPOSE = "weekly_comment".freeze
    TRANSIENT_STATUSES = [ 408, 429 ].freeze
    PROMPTS = Rails.root.join("app/services/claude/prompts")

    def initialize(report, budget: Budget.new, client: nil)
      @report = report
      @budget = budget
      @client = client
    end

    def call
      client # API キーの無い箱で台帳だけ減っていかないよう、記録の前に作る
      budget.record!(purpose: PURPOSE, model: model)
      parse(request)
    end

    def model
      Dopamine.settings.dig(:claude, :curation_model)
    end

    private

    attr_reader :report, :budget

    def client
      @client ||= Client.build
    end

    def request
      client.chat(model: model, provider: Client::PROVIDER, assume_model_exists: true)
            .with_instructions(PROMPTS.join("weekly_comment_system.txt").read.strip)
            .with_max_output_tokens(max_tokens)
            .with_thinking(false)
            .ask_later(user_prompt)
            .generate
    rescue RubyLLM::Error => e
      raise classify(e)
    rescue StandardError => e
      raise Error, "応答の形式が不正 (#{e.class.name.demodulize})"
    end

    # 応答の文面は要求を引用しうるので、失敗の理由には状態だけを残す。
    def classify(error)
      status = error.response&.status
      return TransientError.new(error.try(:timeout?) ? "接続エラー (タイムアウト)" : "接続エラー") if status.nil?
      return Error.new("応答の形式が不正 (HTTP #{status})") if status < 400

      (status >= 500 || TRANSIENT_STATUSES.include?(status) ? TransientError : Error).new("API エラー (HTTP #{status})")
    end

    def parse(message)
      raise MalformedResponse, "応答の形式が不正 (max_tokens で切れた)" if message.finish_reason == :max_tokens

      text = message.content.to_s.strip
      raise MalformedResponse, "応答の形式が不正" if text.empty?

      text
    end

    def user_prompt
      ERB.new(PROMPTS.join("weekly_comment.erb").read, trim_mode: "-").result_with_hash(
        count: report.count, previous_count: report.previous_count, cards: cards
      )
    end

    # 本数は切った後も全体の数を送る。見出しが途中で尽きても、週の量はひとことに正しく出る。
    def cards
      remaining = input_chars
      report.cards.each_with_object([]) do |card, rows|
        break rows unless remaining.positive?

        title, feed = [ card.article.title, card.article.feed.title ].map do |text|
          cut(escape(text), remaining).tap { |kept| remaining -= kept.size }
        end
        rows << { title: title, feed: feed, rarity: rarity(card.tier) }
      end
    end

    def cut(text, limit)
      text.size <= limit ? text : text[0, limit].sub(/&[a-z]*\z/, "")
    end

    def rarity(tier)
      tier ? I18n.t("dopamine.rarities.#{tier}", locale: :ja, default: tier) : "判定中"
    end

    def escape(string)
      string.to_s.gsub("<", "&lt;").gsub(">", "&gt;")
    end

    # 見出しの総量は要約に送る本文 1 本ほどあれば週の傾向は読めるので、専用の鍵が無ければ要約の上限を使う。
    def input_chars
      Dopamine.settings.dig(:claude, :weekly_comment_input_chars) || Dopamine.settings.dig(:claude, :summary_input_chars)
    end

    # 要約と同じく数行の出力なので、専用の鍵が無ければ要約の上限で足りる。
    def max_tokens
      Dopamine.settings.dig(:claude, :weekly_comment_max_tokens) || Dopamine.settings.dig(:claude, :summary_max_tokens)
    end
  end
end
