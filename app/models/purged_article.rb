# 記事を消しても、フィードにはしばらく同じ項目が載り続ける。取り込みはこの目印を見て、消した記事を新着に戻さない。
class PurgedArticle < ApplicationRecord
  REASONS = %w[dismissed unread].freeze

  belongs_to :feed

  validates :url, presence: true
  validates :reason, inclusion: { in: REASONS }
  validates :purged_at, presence: true
end
