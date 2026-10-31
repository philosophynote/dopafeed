# フィードから取り込んだ記事。summary は Claude の 3 行要約（Unit 4 の Job が付ける）、
# content は readability の本文（Unit 3 の Job が付ける）。
# いいね・保存は一人用なので記事に直接残す。読了は Reading（1 記事 1 行）。ADR 0006
class Article < ApplicationRecord
  belongs_to :feed
  has_one :reading, dependent: :destroy

  validates :title, presence: true
  validates :url, presence: true, uniqueness: true

  # 完読していない記事。開いたが未完（Reading はあるが completed_at が nil）は未読のまま
  scope :unread, -> { where.not(id: Reading.completed.select(:article_id)) }
  scope :read, -> { where(id: Reading.completed.select(:article_id)) }
  scope :saved, -> { where.not(liked_at: nil).or(where.not(bookmarked_at: nil)) }
  scope :newest_first, -> { order(published_at: :desc, id: :desc) }

  def saved?
    liked_at.present? || bookmarked_at.present?
  end
end
