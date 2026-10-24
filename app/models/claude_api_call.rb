# Claude API を 1 回呼ぶごとに 1 行。書くのは Claude::Budget#record! だけ
class ClaudeApiCall < ApplicationRecord
  validates :purpose, :model, presence: true
end
