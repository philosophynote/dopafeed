# 購読の単位と取得状態。記事の本文・読了は {Article} に委ねる。
# title は登録時にフィードが名乗る名前を入れ、以後は利用者だけが書く。取得のたびに書き戻すと、付け直した名前が消えるため
# last_fetched_at / last_error / etag / last_modified は {FeedFetcher} が書く。last_fetched_at は試行時刻、last_error が nil なら前回は成功。
# 削除すると記事と、記事経由で読了も消える
class Feed < ApplicationRecord
  has_many :articles, dependent: :destroy

  # strip は全角の空白を落とさず、IME で付いた「　」が名前に残るため
  normalizes :title, with: ->(title) { title.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "") }

  validates :title, presence: true
  validates :url, presence: true, uniqueness: true

  # 購読ごとに数えると SQL が増えるため、記事を読み込まずにまとめて集計する。
  # 一つの購読だけを数えるときも articles を絞ってこの式を通し、件数と未読の数え方を一か所に保つ
  def self.article_counts(articles = Article.all)
    [ articles.group(:feed_id).count, articles.unread.group(:feed_id).count ]
  end
end
