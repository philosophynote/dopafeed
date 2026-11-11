module Claude
  # 長文はトークン代が嵩むわりに 3 行の質が上がらないため、入力を切る。
  # 形式の崩れた応答を保存して表示を崩すより、失敗として残す。
  class Summarizer
    class Error < StandardError; end
    class EmptyContent < Error; end
    class MalformedResponse < Error; end
    class TransientError < Error; end

    PURPOSE = "summary".freeze
    BULLET = "・".freeze
    # 要約の 3 行は製品仕様であり、報酬の調整値ではないので dopamine.yml には置かない。
    LINES = 3
    PROMPTS = Rails.root.join("app/services/claude/prompts")

    # クライアントを遅延生成しないと、本文が空のときも API キーが必要になる。
    def initialize(article, budget: Budget.new, client: nil)
      @article = article
      @budget = budget
      @client = client
    end

    def call
      text = input_text
      raise EmptyContent, "本文が空" if text.blank?

      client # API キーの無い箱で台帳だけ減っていかないよう、記録の前に作る
      budget.record!(purpose: PURPOSE, model: model)
      parse(request(text))
    end

    private

    attr_reader :article, :budget

    def client
      @client ||= Client.build
    end

    def request(text)
      client.messages.create(model: model, max_tokens: max_tokens, system_: system_prompt, messages: [ { role: :user, content: user_prompt(text) } ])
    rescue Anthropic::Errors::APIConnectionError => e
      raise TransientError, "接続エラー (#{e.class.name.demodulize})"
    rescue Anthropic::Errors::RateLimitError, Anthropic::Errors::InternalServerError => e
      raise TransientError, "API エラー (HTTP #{e.status})"
    rescue Anthropic::Errors::APIStatusError => e
      raise Error, "API エラー (HTTP #{e.status})"
    rescue Anthropic::Errors::Error => e
      raise Error, "SDK エラー (#{e.class.name.demodulize})"
    end

    def parse(message)
      raise MalformedResponse, "応答の形式が不正 (max_tokens で切れた)" if message.stop_reason.to_s == "max_tokens"

      lines = message.content.filter_map { |block| block.text if block.respond_to?(:text) }.join.lines.map(&:strip).reject(&:blank?)
      raise MalformedResponse, "応答の形式が不正" unless lines.size == LINES && lines.all? { |line| line.start_with?(BULLET) }

      lines.join("\n")
    end

    def input_text
      Loofah.fragment(article.content.to_s).scrub!(:prune).to_text(encode_special_chars: false)
            .lines.map(&:squish).reject(&:blank?).join("\n").first(input_chars)
    end

    def system_prompt
      PROMPTS.join("summary_system.txt").read.strip
    end

    # 記事の文字列はタグで囲んで渡すので、中の < > を実体にして境界を偽装できなくする（& や引用符はコード片の読みやすさのため残す）
    def user_prompt(text)
      ERB.new(PROMPTS.join("summary.erb").read, trim_mode: "-")
         .result_with_hash(title: escape(article.title), url: escape(article.url), content: escape(text))
    end

    def escape(string)
      string.to_s.gsub("<", "&lt;").gsub(">", "&gt;")
    end

    def model
      Dopamine.settings.dig(:claude, :summary_model)
    end

    def max_tokens
      Dopamine.settings.dig(:claude, :summary_max_tokens)
    end

    def input_chars
      Dopamine.settings.dig(:claude, :summary_input_chars)
    end
  end
end
