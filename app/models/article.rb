class Article < ApplicationRecord
  belongs_to :feed
  has_one :reading, dependent: :destroy

  validates :title, presence: true
  # URL はリンクの href に使うので、javascript: などを通さない。
  validates :url, presence: true, uniqueness: true, format: { with: %r{\Ahttps?://\S+\z}i }

  scope :unread, -> { where(dismissed_at: nil, bookmarked_at: nil).where.not(id: Reading.completed.select(:article_id)) }
  scope :read, -> { where(id: Reading.completed.select(:article_id)) }
  scope :saved, -> { where.not(liked_at: nil).or(where.not(bookmarked_at: nil)) }
  scope :bookmarked, -> { where.not(bookmarked_at: nil).order(bookmarked_at: :desc, id: :desc) }
  scope :newest_first, -> { order(published_at: :desc, id: :desc) }
  scope :awaiting_summary, -> { where(summary: nil, summary_failed_at: nil).where.not(content_fetched_at: nil).where(id: Reading.select(:article_id)) }

  # 新しい方へ戻ると、未完で区切った記事が同じ流れに再び出てしまう。
  def self.next_unread_after(article)
    published_at = arel_table[:published_at]
    id = arel_table[:id]
    older =
      if article.published_at
        published_at.lt(article.published_at)
          .or(published_at.eq(article.published_at).and(id.lt(article.id)))
          .or(published_at.eq(nil))
      else
        published_at.eq(nil).and(id.lt(article.id))
      end
    unread.newest_first.where(older).first
  end

  def saved?
    liked_at.present? || bookmarked_at.present?
  end

  def dismissed?
    dismissed_at.present?
  end

  # 未完の Reading を消すと、取り消したときに出目と滞在を引き継げない。
  def dismiss!(at: Time.current)
    with_lock { update!(dismissed_at: at) unless dismissed? }
    self
  end

  def undismiss!
    update!(dismissed_at: nil)
    self
  end

  def bookmarked?
    bookmarked_at.present?
  end

  # 二度目は最初の時刻を保つ。{.bookmarked} は保存した時刻の順なので、二重送信で順番を動かさない
  def bookmark!(at: Time.current)
    with_lock { update!(bookmarked_at: at) unless bookmarked? }
    self
  end

  def unbookmark!
    update!(bookmarked_at: nil)
    self
  end
end
