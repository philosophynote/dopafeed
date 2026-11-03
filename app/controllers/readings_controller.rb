# 「読む」から記事を開き、戻ってきたら判定して ReadDone を出す。
# 判定の時刻はすべてサーバーの時計。抽選は作るときに 1 回だけ
class ReadingsController < ApplicationController
  def create
    article = Article.find(params[:article_id])
    reading = article.reading || article.build_reading(tier: XpRoulette.draw, opened_at: Time.current)
    reading.new_record? ? reading.save! : reading.reopen!
    # Turbo を切った通常の POST なので、他オリジンへの redirect で記事そのものが開く（iPhone の standalone ではアプリ内シート）
    redirect_to article.url, allow_other_host: true
  end

  def finish
    reading = Reading.find(params[:id])
    reading.return!
    redirect_to reading_path(reading)
  end

  def show
    @reading = Reading.includes(:article).find(params[:id])
    return redirect_to root_path if @reading.returned_at.nil?

    @article = @reading.article
    @goal_articles = Dopamine.settings.dig(:daily_goal, :articles)
    @today_count = Reading.on(ReadingDay.of(@reading.returned_at)).count
    @next_article = Article.unread.newest_first.where.not(id: @article.id).includes(:feed).first
  end
end
