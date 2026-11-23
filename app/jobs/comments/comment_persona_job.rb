module Comments
  # 予算切れの扱いと claude キューは要約と共用する（日次上限は AI の呼び出し全体で一つ）。
  # 本文なし・形式不正・4xx は時間を置いても解消しないため、自動では再試行しない。押し直しは利用者に任せる。
  class CommentPersonaJob < Claude::BaseJob
    discard_on ActiveJob::DeserializationError do |job, error|
      Rails.logger.info("[comments] #{job.class.name} discarded: #{error.message}")
    end

    retry_on Commenter::TransientError, wait: :polynomially_longer do |job, error|
      record_failure(job.arguments.first, error.message)
    end

    limits_concurrency key: ->(comment) { comment.id }

    def perform(comment)
      # 押し直しで積まれた分も、待っている側が出来上がりを受け取れるよう知らせてから終わる
      return self.class.broadcast(comment) unless comment.writing?

      body = Commenter.new(comment.article, comment.persona).call
      comment.update!(body:, failed_at: nil, error: nil)
      self.class.broadcast(comment)
    rescue Commenter::TransientError
      raise
    rescue Commenter::Error => e
      self.class.record_failure(comment, e.message)
    rescue Claude::Budget::Exhausted
      # 捨てるのは親の discard_on。枠を消すと、翌日に同じ人を頼み直す手段が無くなる
      self.class.record_failure(comment, "今日の上限")
      raise
    rescue StandardError => e
      # 設定の誤りは畳まずに上げるが、記録しないと書いている途中のまま残り、押し直す手段が無くなる。
      # 例外の文面は SQL や要求を含みうるので、クラス名だけを残す
      self.class.record_failure(comment, "予期しない失敗 (#{e.class.name.demodulize})")
      raise
    end

    def self.record_failure(comment, message)
      comment.with_lock do
        comment.update!(failed_at: Time.current, error: message) unless comment.written?
      end
      broadcast(comment)
    end

    def self.broadcast(comment)
      comment.reload
      article = comment.article
      lineup = PersonaComment.lineup(article)
      if lineup.any? && lineup.all?(&:written?)
        # カードだけ替えると、欄は書いている途中の印と購読を持ったまま残る。
        # 判定の後に別の組が押されていれば、その欄を古い組で上書きして購読を外さないよう、同じ組を描いている欄だけに送る
        box = ActionView::RecordIdentifier.dom_id(article, :comments_box)
        Turbo::StreamsChannel.broadcast_replace_to(article, :comments, targets: "##{box}[data-lineup='#{lineup.map(&:id).join("-")}']",
                                                                     partial: "comments/box", locals: { article:, lineup: })
      elsif comment.persona.enabled?
        Turbo::StreamsChannel.broadcast_replace_to(article, :comments, target: ActionView::RecordIdentifier.dom_id(comment),
                                                                     partial: "comments/card", locals: { comment: })
      else
        # 本文は戻したときに出せるよう残すが、外した人のカードは欄に出さない
        Turbo::StreamsChannel.broadcast_remove_to(article, :comments, target: ActionView::RecordIdentifier.dom_id(comment))
      end
    end
  end
end
