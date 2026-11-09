# 手に入れたカード（完読した {Reading}）の図鑑。読み取り専用で、カードを作るのは判定（{Reading#return!}）だけ。
# 一覧は 1 回で読み込み、段ごとの数もその行から数える（同じ表を何度も舐めない）
class CollectionController < ApplicationController
  def show
    cards = Reading.completed.includes(article: :feed).order(completed_at: :desc, id: :desc).load
    @cards_count = cards.size
    @cards_by_day = cards.group_by { |card| ReadingDay.of(card.completed_at) }
    @counts = cards.map(&:tier).tally
    @streak_days = ReadingStreak.days
    @unread_count = unread_count
  end
end
