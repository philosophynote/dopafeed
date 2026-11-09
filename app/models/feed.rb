# 取得のたびに title を書き戻すと、利用者が付け直した名前が消える。
class Feed < ApplicationRecord
  has_many :articles, dependent: :destroy

  # strip は全角の空白を落とさず、IME で付いた「　」が名前に残るため
  normalizes :title, with: ->(title) { title.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "") }

  validates :title, presence: true
  validates :url, presence: true, uniqueness: true

  # 購読ごとに数えると SQL が増えるため、記事を読み込まずにまとめて集計する。
  def self.article_counts(articles = Article.all)
    [ articles.group(:feed_id).count, articles.unread.group(:feed_id).count ]
  end
end
