# フィードから取り込んだ記事。
# summary は Claude の 3 行要約（Unit 4 の Job が付ける）、content はフィードの entry 本文（{FeedFetcher} が付ける。HTML のまま。記事ページの本文取得は Unit 3b）。
# guid はフィード内の重複排除の鍵（entry_id、無ければ url。[feed_id, guid] は一意）。既存の記事は取得で更新しない。
# いいね・保存は一人用なので記事に直接残す（liked_at / bookmarked_at）。読了は {Reading}（1 記事 1 行）。ADR 0006
#
# @!method self.unread
#   完読していない記事。開いたが未完（Reading はあるが completed_at が nil）は未読のまま
#   @return [ActiveRecord::Relation<Article>]
# @!method self.read
#   完読した記事
#   @return [ActiveRecord::Relation<Article>]
# @!method self.saved
#   いいねか保存が付いた記事（Saved 画面はこの 2 つを束ねて出す）
#   @return [ActiveRecord::Relation<Article>]
# @!method self.newest_first
#   published_at の新しい順（同時刻は id の大きい順）
#   @return [ActiveRecord::Relation<Article>]
class Article < ApplicationRecord
  belongs_to :feed
  has_one :reading, dependent: :destroy

  validates :title, presence: true
  validates :url, presence: true, uniqueness: true

  scope :unread, -> { where.not(id: Reading.completed.select(:article_id)) }
  scope :read, -> { where(id: Reading.completed.select(:article_id)) }
  scope :saved, -> { where.not(liked_at: nil).or(where.not(bookmarked_at: nil)) }
  scope :newest_first, -> { order(published_at: :desc, id: :desc) }

  # @return [Boolean] いいねか保存のどちらかが付いているか
  def saved?
    liked_at.present? || bookmarked_at.present?
  end
end
