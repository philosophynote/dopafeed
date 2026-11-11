class ClaudeApiCall < ApplicationRecord
  validates :purpose, :model, presence: true
end
