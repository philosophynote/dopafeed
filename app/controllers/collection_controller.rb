# 手に入れたカード（完読した {Reading}）の図鑑。読み取り専用で、カードを作るのは判定（{Reading#return!}）だけ。
# 束の日付は {ReadingDay} で切り、数は段ごとに数えてビューに渡す
class CollectionController < ApplicationController
  def show
    cards = Reading.completed.includes(article: :feed).order(completed_at: :desc, id: :desc).load
    @cards_count = cards.size
    @cards_by_day = cards.group_by { |card| ReadingDay.of(card.completed_at) }
    @counts = Reading.completed.group(:tier).count
    @streak_days = ReadingStreak.days
    @unread_count = Article.unread.count
  end
end
