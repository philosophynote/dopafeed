# 「読む」から記事を開き、戻ってきたら判定して ReadDone を出す。
# 判定の時刻はすべてサーバーの時計。抽選は作るときに 1 回だけ
class ReadingsController < ApplicationController
  # Turbo の POST には抽選結果を埋めたルーレットのモーダルを返す（演出はクライアント、結果はサーバー）。
  # JS が無い通常の POST は演出なしで記事へ redirect する
  def create
    @article = Article.find(params[:article_id])
    @reading = @article.reading || @article.build_reading(tier: XpRoulette.draw, opened_at: Time.current)
    @reading.new_record? ? @reading.save! : @reading.reopen!
    respond_with_roulette
  rescue ActiveRecord::RecordNotUnique
    # 二重タップで同じ記事の行が同時に作られたら、先に入った方を使って進む
    @reading = Reading.find_by!(article: @article)
    respond_with_roulette
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

  # 全画面演出。完読済みでも開ける（戻るで Main に帰っても結果は保持され、同じ記事を再び読めば同じ画面に来る）
  def jackpot
    @reading = Reading.includes(article: :feed).find(params[:id])
    return redirect_to root_path unless @reading.jackpot?

    @article = @reading.article
  end

  private

  def respond_with_roulette
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @article.url, allow_other_host: true }
    end
  end
end
