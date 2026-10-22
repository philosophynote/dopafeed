module Claude
  # Claude を呼ぶ Job の親。中身（要約・選定・コメント・クエスト）は Unit 4 以降で足す。
  # 予算切れは業務上の「今日はもう呼ばない」なので再試行せず捨てる。
  class BaseJob < ApplicationJob
    queue_as :claude

    discard_on Claude::Budget::Exhausted do |job, error|
      Rails.logger.warn("[claude] #{job.class.name} discarded: #{error.message}")
    end
  end
end
