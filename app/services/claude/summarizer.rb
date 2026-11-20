module Claude
  # 長文はトークン代が嵩むわりに 3 行の質が上がらないため、入力を切る。
  # 形式の崩れた応答を保存して表示を崩すより、失敗として残す。
  class Summarizer
    class Error < StandardError; end
    class EmptyContent < Error; end
    class MalformedResponse < Error; end
    class TransientError < Error; end

    PURPOSE = "summary".freeze
    TRANSIENT_STATUSES = [ 408, 429 ].freeze
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

    # gem はモデルの既定で思考を有効にし、3 行ぶんの max_tokens を思考が食って切れるので、明示して切る。
    # ask はツールを求める応答に答えて呼び直し続け、台帳の 1 行を超えて払うので、1 回だけ生成する generate を使う。
    def request(text)
      client.chat(model: model, provider: Client::PROVIDER, assume_model_exists: true)
            .with_instructions(system_prompt)
            .with_max_output_tokens(max_tokens)
            .with_thinking(false)
            .ask_later(user_prompt(text))
            .generate
    rescue RubyLLM::Error => e
      raise classify(e)
    rescue StandardError => e
      raise Error, "応答の形式が不正 (#{e.class.name.demodulize})"
    end

    # gem の例外クラスは 408 や一覧に無い 5xx を素の Error にするので、状態で分ける。
    # 応答の文面は要求を引用しうるので、失敗の理由には状態だけを残す。
    def classify(error)
      status = error.response&.status
      return TransientError.new(error.try(:timeout?) ? "接続エラー (タイムアウト)" : "接続エラー") if status.nil?
      return Error.new("応答の形式が不正 (HTTP #{status})") if status < 400

      (status >= 500 || TRANSIENT_STATUSES.include?(status) ? TransientError : Error).new("API エラー (HTTP #{status})")
    end

    def parse(message)
      raise MalformedResponse, "応答の形式が不正 (max_tokens で切れた)" if message.finish_reason == :max_tokens

      lines = message.content.to_s.lines.map(&:strip).reject(&:blank?)
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
