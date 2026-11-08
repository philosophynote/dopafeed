# 入口の一覧。未読の記事と、今日の進み（ゴール・ストリーク・カードの枚数・連続）を一度に出す読み取り専用
class MainController < ApplicationController
  include TodayStatus

  def show
    @articles = Article.unread.newest_first.includes(:feed).load
    @unread_count = @articles.size
    load_today_status
  end
end
