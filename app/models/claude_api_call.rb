# Claude API を 1 回呼ぶごとに 1 行。日次の上限を数える台帳なので、呼び出しの成否に関わらず呼ぶ前に書く
class ClaudeApiCall < ApplicationRecord
  validates :purpose, :model, presence: true
end
