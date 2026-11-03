module Claude
  # 記事 1 本を日本語 3 行に要約する。SDK を呼ぶのはここだけで、呼ぶ前に {Budget} の台帳を 1 行進める。
  # DB には書かない。入出力は文字列と例外で、保存と失敗の記録は Job の仕事。
  # 本文はタグを落として先頭の summary_input_chars 文字だけ渡す（長文はトークン代が嵩むわりに 3 行の質が上がらない）。
  # 応答は「・」で始まる 3 行以外を受け付けない。崩れた応答を保存して読む側を崩すより、失敗として残して人の目に触れる方がよい。
  # SDK の例外はここで自前の例外に畳む。Job とモデルは Anthropic:: を知らない
  class Summarizer
    # 記録して終わりにする失敗（本文なし・形式不正・4xx・SDK の設定や変換の失敗）
    class Error < StandardError; end
    # 本文がタグを除くと空。記事ページもフィードも本文をくれなかった
    class EmptyContent < Error; end
    # 応答が 3 行の形になっていない。max_tokens で切れた場合も含む
    class MalformedResponse < Error; end
    # 待てば通るかもしれない失敗（接続エラー・タイムアウト・429・5xx）
    class TransientError < Error; end

    PURPOSE = "summary".freeze
    BULLET = "・".freeze
    # 要約の行数。docs/SPEC.md が 3 行と定め、読む側もそれを前提に組む。報酬の数字ではないので dopamine.yml には置かない。
    # prompts/summary_system.txt の「3 行」と対で、変えるなら両方
    LINES = 3
    PROMPTS = Rails.root.join("app/services/claude/prompts")

    # @param budget [Budget] 上限を変えるテストのために差し替えられる
    # @param client [Anthropic::Client, nil] nil なら呼ぶ直前に {Client.build}。本文が空なら API キーが無くても失敗を返せる
    def initialize(article, budget: Budget.new, client: nil)
      @article = article
      @budget = budget
      @client = client
    end

    # @return [String] 「・」始まりの 3 行を改行で結んだもの
    # @raise [EmptyContent, MalformedResponse, Error, TransientError]
    # @raise [Budget::Exhausted] 今日の上限。呼ぶ前に投げるので API には届かない
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

    # テキスト以外のブロック（tool_use など）は無視する。無ければ 0 行なので形式不正になる
    def parse(message)
      raise MalformedResponse, "応答の形式が不正 (max_tokens で切れた)" if message.stop_reason.to_s == "max_tokens"

      lines = message.content.filter_map { |block| block.text if block.respond_to?(:text) }.join.lines.map(&:strip).reject(&:blank?)
      raise MalformedResponse, "応答の形式が不正" unless lines.size == LINES && lines.all? { |line| line.start_with?(BULLET) }

      lines.join("\n")
    end

    # script / style はタグごと落とし（readability を通らなかったフィード由来の本文に残ることがある）、ブロック要素の境界を改行にする
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
