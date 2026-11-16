module Judgments
  # gem と Job の両方で再試行すると回数が掛け算になるため、gem 側は切る。
  # 応答の文面は要求を引用しうるので、失敗の理由には状態だけを残す。
  class ArticleScorer
    class Error < StandardError; end
    class EmptyContent < Error; end
    class TransientError < Error; end

    PURPOSE = "rarity_judgment".freeze
    PROVIDER = :openrouter
    TRANSIENT = [ RubyLLM::ConnectionError, RubyLLM::RateLimitError, RubyLLM::ServerError,
                  RubyLLM::ServiceUnavailableError, RubyLLM::OverloadedError ].freeze

    Result = Data.define(:scores, :model, :input_tokens, :cost)

    def self.configured?
      Dopamine.settings[:judgment].present? && ENV["OPENROUTER_API_KEY"].present?
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
      result(judge({ title: article.title, body: body }, context))
    end

    private

    attr_reader :article, :budget

    def settings
      Dopamine.settings.fetch(:judgment)
    end

    def build_context
      api_key = ENV.fetch("OPENROUTER_API_KEY")
      RubyLLM.context do |config|
        config.openrouter_api_key = api_key
        config.request_timeout = settings.fetch(:timeout_seconds)
        config.max_retries = 0
      end
    end

    # 同梱のモデル一覧に無い新しい版を yml に書いても呼べるよう、一覧での存在確認は省く。
    def judge(input, context)
      ArticleRarityJudge.judge(input, model: settings.fetch(:model), provider: PROVIDER, assume_model_exists: true, context: context)
    rescue *TRANSIENT => e
      raise TransientError, describe(e)
    rescue RubyLLM::Error => e
      raise Error, describe(e)
    end

    def describe(error)
      status = error.response&.status
      return "API エラー (HTTP #{status})" if status && status >= 400
      return "応答の形式が不正" if status

      "接続エラー (#{error.class.name.demodulize})"
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
