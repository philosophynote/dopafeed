class PersonaComment < ApplicationRecord
  belongs_to :article
  # 外した人のコメントも戻したときにまた出せるよう、人物の表とは外部キーで結ばず slug で引く
  belongs_to :persona, primary_key: :slug, inverse_of: false

  validates :body, presence: true, allow_nil: true

  scope :by_enabled_personas, -> { joins(:persona).where(personas: { enabled: true }) }
  scope :written, -> { where.not(body: nil) }

  # 押したときに選んだ組を、取り直しや再読込でも同じ顔ぶれで出す。組は同じ時刻の shown_at で束ねる。
  # 組の人を外して欠けたら、乱数を使わず作った順に補う（再読込のたびに補う人が変わらないように）。
  # 記録を始める前の行には時刻が無いので、そのときだけ選び直す
  def self.lineup(article)
    saved = article.persona_comments.by_enabled_personas.includes(:persona).to_a
    shown_at = saved.filter_map(&:shown_at).max
    return pick(saved, except: []) unless shown_at

    group, others = saved.sort_by(&:id).partition { |comment| comment.shown_at == shown_at }
    group + others.first([ Dopamine.settings.dig(:comments, :personas_shown) - group.size, 0 ].max)
  end

  # 押したときの組の人。外した人も含めるのは、外す前に描いた欄からの押下を古い押下と見分けないため
  def self.recorded_lineup(article)
    shown_at = article.persona_comments.maximum(:shown_at)
    shown_at ? article.persona_comments.where(shown_at:).pluck(:persona_id) : []
  end

  # 足りなければ直前の組の人も使うのは、人物を外した後に欠けた組を出さないため。
  # 書いている途中、失敗の順に新しく頼んだものを先に取り、作っている人が組から押し出されないようにする
  def self.pick(saved, except:)
    count = Dopamine.settings.dig(:comments, :personas_shown)
    rest = saved.reject { |comment| comment.persona_id.in?(except) }
    pool = rest.size >= count ? rest : saved
    unfinished, written = pool.partition { |comment| !comment.written? }
    (unfinished.sort_by { |comment| [ comment.writing? ? 0 : 1, -comment.updated_at.to_f ] } + written.shuffle).first(count)
  end

  def state
    return :written if body?
    return :failed if failed_at? || stale?

    :writing
  end

  # Job が記録の前に止まると（旧版のワーカーが取った、プロセスが落ちたなど）、本文も失敗も書かれずに残る。
  # 頼み直せるよう、yml の秒数より古い書いている途中は失敗として扱う。鍵が無ければ扱いを変えない
  def stale?
    after = Dopamine.settings.dig(:comments, :stale_after_seconds)
    after.present? && updated_at.present? && updated_at < after.seconds.ago
  end

  def written? = state == :written
  def failed? = state == :failed
  def writing? = state == :writing
end
