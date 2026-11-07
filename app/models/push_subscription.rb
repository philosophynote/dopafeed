# Web Push の購読。端末（ブラウザ）が作った PushSubscription の endpoint と鍵（p256dh / auth）を 1 端末 1 行で預かる。
# 一人用なので user_id は持たない（ADR 0006）。endpoint が一意なのは、同じ端末が購読をやり直しても行を増やさないため。
# digest_sent_on / streak_warning_sent_on は「その端末にその日の通知を送ったか」。送る側が 1 日 1 回を守るための印で、ここでは書かない。
# 送信と、失効した購読（410）の削除は送る側の責務（ADR 0013）
class PushSubscription < ApplicationRecord
  validates :endpoint, presence: true, uniqueness: true, format: { with: %r{\Ahttps://\S+\z} }
  validates :p256dh, :auth, presence: true

  # 印が nil の行も拾うために where.not ではなく or（SQL の != は NULL を落とす）
  scope :not_sent_on, ->(column, day) { where(column => nil).or(where(arel_table[column].lt(day))) }

  # 端末からの購読を保存する。同じ endpoint なら鍵と UA を上書きする（ブラウザが鍵を作り直したとき、古い鍵では送れなくなるため）。
  # 保存できたかは返した行の errors で見る
  #
  # @return [PushSubscription] 保存を試みた行
  def self.register(endpoint:, p256dh:, auth:, user_agent:)
    subscription = find_or_initialize_by(endpoint: endpoint)
    subscription.assign_attributes(p256dh: p256dh, auth: auth, user_agent: user_agent)
    subscription.save
    subscription
  end
end
