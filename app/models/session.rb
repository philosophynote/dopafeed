# ログイン 1 回ぶんの記録。cookie の session_id がこの行を指す。期限の判断はここに置き、
# コントローラ（Authentication concern）と ActionCable の接続が同じ基準で通す
class Session < ApplicationRecord
  # 最後に使ってからこの間あいた Session は、cookie が残っていても通さない。
  # 行に期限が無いと、盗まれた cookie がいつまでも効くため（ADR 0005）
  REMEMBER_FOR = 1.year

  belongs_to :user

  scope :unexpired, -> { where(updated_at: REMEMBER_FOR.ago..) }
end
