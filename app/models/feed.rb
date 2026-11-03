# 購読している RSS / Atom。
# last_fetched_at / last_error / etag / last_modified は {FeedFetcher} が書く。last_fetched_at は試行時刻、last_error が nil なら前回は成功。
# 削除すると記事と、記事経由で読了も消える
class Feed < ApplicationRecord
  has_many :articles, dependent: :destroy

  validates :title, presence: true
  validates :url, presence: true, uniqueness: true
end
