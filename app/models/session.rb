class Session < ApplicationRecord
  # 行に期限が無いと、盗まれた cookie がいつまでも効くため（ADR 0005）。
  REMEMBER_FOR = 1.year

  belongs_to :user

  scope :unexpired, -> { where(updated_at: REMEMBER_FOR.ago..) }
end
