# 購読している RSS / Atom。last_fetched_at / last_error / etag / last_modified は Unit 3 の取得 Job が書く
# （last_error が nil なら前回は成功）。フィード重み（Thompson）は第二の陣
class Feed < ApplicationRecord
  has_many :articles, dependent: :destroy

  validates :title, presence: true
  validates :url, presence: true, uniqueness: true
end
