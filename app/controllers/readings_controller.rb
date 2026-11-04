# 「読む」で抽選して記事を開き、リーダーで末尾まで読んだら判定して次の記事を開く。
# 判定の時刻はすべてサーバーの時計。抽選は行を作るときに 1 回だけ。
# finish と show は元サイトへ出て戻ってくる経路の名残で、撤去するまで残す
class ReadingsController < ApplicationController
  # Turbo の POST には抽選結果を埋めたルーレットのモーダルを返す（演出はクライアント、結果はサーバー）。
  # JS が無い通常の POST は演出なしでリーダーへ redirect する
  def create
    @article = Article.find(params[:article_id])
    @reading = Reading.open!(@article)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to read_article_path(@article) }
    end
  end

  # 記事の末尾まで読んだ。判定し、その下に古い方の次の未読を開いて継ぎ足す。
  # 次の記事の行（抽選と開いた時刻）をここで作るのは、GET の描画で書き込まないため。
  # 判定済みなら何もしない（自動送信とボタンの二重送信、再読込）
  def advance
    @reading = Reading.includes(article: :feed).find(params[:id])
    return head(:no_content) if @reading.returned_at.present?

    @reading.return!
    following = Article.next_unread_after(@reading.article)
    @next_reading = following && Reading.open!(following)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @next_reading ? read_article_path(@next_reading.article) : root_path }
    end
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
end
