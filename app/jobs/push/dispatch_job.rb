module Push
  # 10 分おきに回り、時刻を過ぎていて今日の印が無い購読に通知を送って読書日を書く（ADR 0013）。
  # 遅れても同じ読書日なら送る（止まっていた朝の分が昼に届くのは許す）。印は送れたときだけ書くので、失敗した端末には次の回に送り直す。
  # 文面は購読ごとではなく通知ごとに 1 回組み立て、送る相手がいなければ組み立てない
  class DispatchJob < ApplicationJob
    queue_as :push

    NOTICES = [ Digest, StreakWarning ].freeze

    def perform
      return unless Vapid.configured?

      day = ReadingDay.of
      NOTICES.each do |notice_class|
        notice = notice_class.new(day)
        next unless notice.due?

        pending = PushSubscription.not_sent_on(notice_class.sent_on_column, day)
        next if pending.none?

        payload = notice.payload
        next if payload.nil?

        pending.find_each do |subscription|
          subscription.update!(notice_class.sent_on_column => day) if sender.deliver(subscription, payload)
        end
      end
    end

    private

    def sender
      @sender ||= Sender.new
    end
  end
end
