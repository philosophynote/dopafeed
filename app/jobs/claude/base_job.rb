module Claude
  # 予算切れは時間を置いても同じ日には解消しないため、再試行しない。
  class BaseJob < ApplicationJob
    queue_as :claude

    discard_on Claude::Budget::Exhausted do |job, error|
      Rails.logger.warn("[claude] #{job.class.name} discarded: #{error.message}")
    end
  end
end
