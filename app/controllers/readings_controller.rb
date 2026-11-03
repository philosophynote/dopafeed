# 「読む」から記事を開き、戻ってきたら判定して ReadDone を出す。
# 判定の時刻はすべてサーバーの時計。抽選は作るときに 1 回だけ
class ReadingsController < ApplicationController
  def create
    article = Article.find(params[:article_id])
    reading = article.reading || article.build_reading(tier: XpRoulette.draw, opened_at: Time.current)
    reading.new_record? ? reading.save! : reading.reopen!
    redirect_to article.url, allow_other_host: true
  rescue ActiveRecord::RecordNotUnique
    # 二重タップで同じ記事の行が同時に作られたら、先に入った方を使って記事へ進む
    redirect_to article.url, allow_other_host: true
  end

  # 開いたまま戻っていない行のうち最新を閉じる。無ければ Main へ戻すだけ
  def finish
    reading = Reading.pending.first
    return redirect_to root_path if reading.nil?

    reading.return!
    redirect_to reading_path(reading)
  end

  def show
    @reading = Reading.includes(article: :feed).find(params[:id])
    return redirect_to root_path if @reading.returned_at.nil?

    @article = @reading.article
    @goal_articles = Dopamine.settings.dig(:daily_goal, :articles)
    @today_count = Reading.on(ReadingDay.of(@reading.returned_at)).count
    @next_article = Article.unread.newest_first.where.not(id: @article.id).includes(:feed).first
  end
end
