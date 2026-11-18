module Judgments
  # gem と Job の両方で再試行すると回数が掛け算になるため、gem 側は切る。
  # 応答の文面は要求を引用しうるので、失敗の理由には状態だけを残す。
  class ArticleScorer
    class Error < StandardError; end
    class EmptyContent < Error; end
    class TransientError < Error; end
    class RejectedError < Error; end

    PURPOSE = "rarity_judgment".freeze
    PROVIDER = :typesafe
    TRANSIENT_STATUSES = [ 408, 429 ].freeze

    Result = Data.define(:scores, :model, :input_tokens, :cost)

    def self.configured?
      Dopamine.settings[:judgment].present? && ENV["TYPESAFE_API_KEY"].present?
    end

    def initialize(article, budget: Claude::Budget.new)
      @article = article
      @budget = budget
    end

    def call
      body = input_text
      raise EmptyContent, "本文が空" if body.blank?

      context = build_context # API キーの無い箱で台帳だけ減っていかないよう、記録の前に作る
      budget.record!(purpose: PURPOSE, model: settings.fetch(:model))
      score({ title: article.title, body: body }, context)
    end

    private

    attr_reader :article, :budget

    def settings
      Dopamine.settings.fetch(:judgment)
    end

    def build_context
      api_key = ENV.fetch("TYPESAFE_API_KEY")
      RubyLLM.context do |config|
        config.typesafe_api_key = api_key
        config.request_timeout = settings.fetch(:timeout_seconds)
        config.max_retries = 0
      end
    end

    # 同梱のモデル一覧に無い新しい版を yml に書いても呼べるよう、一覧での存在確認は省く。
    # gem が RubyLLM::Error 以外を上げたとき、そのまま外へ出すと、台帳に記録済みのまま失敗を残せず、開き直すたびに払い直す。
    def score(input, context)
      result(ArticleRarityJudge.judge(input, model: settings.fetch(:model), provider: PROVIDER, assume_model_exists: true, context: context))
    rescue Error
      raise
    rescue RubyLLM::Error => e
      raise classify(e)
    rescue StandardError => e
      raise Error, "応答の形式が不正 (#{e.class.name.demodulize})"
    end

    # gem の例外クラスは 408 や一覧に無い 5xx を素の Error にするので、状態で分ける。
    # 4xx を記事の失敗として行に残すと、モデル名の誤りや API の変更で拒まれた間に開いた記事が、直した後も判定されない。
    # 記事ごとの拒否だった場合は開き直すたびに送り直すが、日次の上限で止まる。
    def classify(error)
      status = error.response&.status
      return TransientError.new("接続エラー (#{error.class.name.demodulize})") if status.nil?
      return Error.new("判定として読めない応答 (HTTP #{status})") if status < 400

      (status >= 500 || TRANSIENT_STATUSES.include?(status) ? TransientError : RejectedError).new("API エラー (HTTP #{status})")
    end

    # 段の範囲を外れた値を保存の検証で落とすと、Job が失敗を残せずに死ぬ。
    def result(judgment)
      scores = ArticleJudgment::AXES.index_with { |axis| judgment.fetch(axis).score }
      raise Error, "応答の形式が不正" unless scores.values.all? { |score| score.is_a?(Numeric) && score.between?(0, ArticleJudgment::LEVELS - 1) }

      Result.new(scores: scores, model: judgment.model, input_tokens: judgment.tokens.input, cost: judgment.cost.total)
    end

    def input_text
      Loofah.fragment(article.content.to_s).scrub!(:prune).to_text(encode_special_chars: false)
            .lines.map(&:squish).reject(&:blank?).join("\n").first(settings.fetch(:input_chars))
    end
  end
end
