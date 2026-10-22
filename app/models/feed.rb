# 購読している RSS / Atom。取得状態・XP などの列は Unit 2 で足す
class Feed < ApplicationRecord
  has_many :articles, dependent: :destroy

  validates :title, presence: true
  validates :url, presence: true, uniqueness: true
end
