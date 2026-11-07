# フィードから取り込んだ記事。
# summary は Claude の 3 行要約（Job が後から付ける。取り込み直後は nil）。summary_failed_at / summary_error は要約の失敗。
# 失敗は自動では再試行せず、人が {.retry_failed_summaries} で戻したときだけ拾い直す。content は HTML: まず {FeedFetcher} がフィードの entry 本文をそのまま入れ、
# {ArticleContentFetcher} が記事ページから readability で抜いた本文（段落・見出し・コード・リンクだけ残る）で置き換える。
# content_fetched_at は試行時刻、content_error が nil なら成功。
# guid はフィード内の重複排除の鍵（entry_id、無ければ url。[feed_id, guid] は一意）。
# いいね・保存は一人用なので記事に直接残す（liked_at / bookmarked_at）。読了は {Reading}（1 記事 1 行）。ADR 0006
# 興味なし（dismissed_at）も記事に残す。読んでいないので {Reading} は作らず、XP も読了の数も動かない（ADR 0012）
#
# @!method self.unread
#   完読していない記事。開いたが未完（Reading はあるが completed_at が nil）は未読のまま。興味なしは除く
#   @return [ActiveRecord::Relation<Article>]
# @!method self.read
#   完読した記事
#   @return [ActiveRecord::Relation<Article>]
# @!method self.saved
#   いいねか保存が付いた記事
#   @return [ActiveRecord::Relation<Article>]
# @!method self.newest_first
#   published_at の新しい順（同時刻は id の大きい順）
#   @return [ActiveRecord::Relation<Article>]
# @!method self.awaiting_summary
#   要約待ちの記事。本文取得を試す前（content_fetched_at が nil）は含めない。フィードの薄い本文を要約すると、その後に本文が入っても二度と直らない
#   @return [ActiveRecord::Relation<Article>]
# @!method self.summary_failed
#   要約に失敗した記事
#   @return [ActiveRecord::Relation<Article>]
class Article < ApplicationRecord
  belongs_to :feed
  has_one :reading, dependent: :destroy

  validates :title, presence: true
  # http(s) 以外を弾くのは、url がリンクの href にそのまま入るため（javascript: などを通さない）
  validates :url, presence: true, uniqueness: true, format: { with: %r{\Ahttps?://\S+\z}i }

  scope :unread, -> { where(dismissed_at: nil).where.not(id: Reading.completed.select(:article_id)) }
  scope :read, -> { where(id: Reading.completed.select(:article_id)) }
  scope :saved, -> { where.not(liked_at: nil).or(where.not(bookmarked_at: nil)) }
  scope :newest_first, -> { order(published_at: :desc, id: :desc) }
  scope :awaiting_summary, -> { where(summary: nil, summary_failed_at: nil).where.not(content_fetched_at: nil) }
  scope :summary_failed, -> { where(summary: nil).where.not(summary_failed_at: nil) }

  # 要約の失敗の記録を消して要約待ちに戻す。失敗の理由で選り分けないのは、本文が空の記事は API を呼ぶ前にまた失敗し、予算を減らさないから
  #
  # @return [Integer] 戻した本数
  def self.retry_failed_summaries
    summary_failed.update_all(summary_failed_at: nil, summary_error: nil, updated_at: Time.current)
  end

  # 続けて読む次の未読。newest_first の順で article のすぐ後ろ（古い方）の 1 本。
  # 古い方へしか進まないので、未完で区切った記事が同じ流れに二度出ない。published_at の無い記事は SQLite の降順どおり最後に来る
  #
  # @return [Article, nil] 尽きたら nil
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

  # @return [Boolean] いいねか保存のどちらかが付いているか
  def saved?
    liked_at.present? || bookmarked_at.present?
  end

  def dismissed?
    dismissed_at.present?
  end

  # 読まずに片付ける。二度目は最初の時刻を保つ（二重送信で記録を動かさない）。同時に 2 本届いても最初の時刻を保つよう、行をロックして見直す。
  # 開いたが未完の {Reading} は消さない。出目と滞在は戻したときにそのまま使い、その後に読み終えれば完読にもなる（読んだのは事実。判定は dismissed_at を見ない）
  def dismiss!(at: Time.current)
    with_lock { update!(dismissed_at: at) unless dismissed? }
    self
  end

  def undismiss!
    update!(dismissed_at: nil)
    self
  end
end
