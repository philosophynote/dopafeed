# 同じ endpoint の再購読で行を増やさない。一人用なので user_id は持たない（ADR 0006）。
class PushSubscription < ApplicationRecord
  validates :endpoint, presence: true, uniqueness: true, format: { with: %r{\Ahttps://\S+\z} }
  validates :p256dh, :auth, presence: true

  # 印が nil の行も拾うために where.not ではなく or（SQL の != は NULL を落とす）
  scope :not_sent_on, ->(column, day) { where(column => nil).or(where(arel_table[column].lt(day))) }

  # 再購読で作り直した鍵を保存しないと、古い鍵では端末へ送れない。
  def self.register(endpoint:, p256dh:, auth:, user_agent:)
    subscription = find_or_initialize_by(endpoint: endpoint)
    subscription.assign_attributes(p256dh: p256dh, auth: auth, user_agent: user_agent)
    subscription.save
    subscription
  end
end
