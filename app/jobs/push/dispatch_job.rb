module Push
  # 定期的に回り（間隔は config/recurring.yml）、時刻を過ぎていて今日の印が無い購読に通知を送って読書日を書く（ADR 0013）。
  # 遅れても同じ読書日なら送る（止まっていた朝の分が昼に届くのは許す）。印は送れたときだけ書くので、失敗した端末には次の回に送り直す。
  # 通知が「今日は出さない」（payload が nil）と決めた回は、送らずに印だけ書いてその日を閉じる。後から条件が整っても深夜に鳴らさないため。
  # 文面は購読ごとではなく通知ごとに 1 回組み立て、送る相手がいなければ組み立てない。
  # 前の回が終わる前に次の回が来たら捨てる（印を書く前に重なると同じ端末に二重に届く）
  class DispatchJob < ApplicationJob
    queue_as :push
    limits_concurrency key: "dispatch", on_conflict: :discard

    NOTICES = [ Digest, StreakWarning ].freeze

    def perform
      return unless Vapid.configured?

      sender = Sender.new
      day = ReadingDay.of
      NOTICES.each do |notice_class|
        notice = notice_class.new(day)
        next unless notice.due?

        pending = PushSubscription.not_sent_on(notice_class.sent_on_column, day)
        next if pending.none?

        payload = notice.payload
        next pending.update_all(notice_class.sent_on_column => day) if payload.nil?

        pending.find_each do |subscription|
          subscription.update!(notice_class.sent_on_column => day) if sender.deliver(subscription, payload)
        end
      end
    rescue Sender::ConfigurationError => e
      Rails.logger.error("[push] #{e.message}")
    end
  end
end
