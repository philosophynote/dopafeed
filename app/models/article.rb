# フィードから取り込んだ記事。summary は Claude の 3 行要約（Unit 4 の Job が付ける）
class Article < ApplicationRecord
  belongs_to :feed

  validates :title, presence: true
  validates :url, presence: true, uniqueness: true
end
