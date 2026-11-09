module Push
  # 「今日は出さない」回も送信済みにしないと、後から条件が整った深夜に通知が鳴る。
  # 前回と重なると送信済みの印を書く前に二重送信するため、重複実行は捨てる。
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
