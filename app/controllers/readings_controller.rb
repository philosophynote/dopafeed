# 「読む」で抽選して記事を開き、元の記事を開いて戻ったら判定する（リーダーでは次の記事を開いて継ぎ足し、一覧の広げた欄では区切りだけ返す）。
# 判定の時刻はすべてサーバーの時計。抽選は行を作るときに 1 回だけ。
# 行を作った記事（= 読むと決めた記事）の要約はここで積む。読まない記事に払わないため（ADR 0015）
class ReadingsController < ApplicationController
  include TodayStatus

  # Turbo の POST には抽選結果を埋めたルーレットのモーダルを返す（演出はクライアント、結果はサーバー）。
  # expand が付いた POST には、画面を移らずに行の下へ広げる欄（出目・要約・元記事へのリンク）を返す。待ち時間を削るためモーダルは回さない（ADR 0019）。
  # JS が無い通常の POST は演出なしでリーダーへ redirect する
  def create
    @article = Article.find(params[:article_id])
    @reading = Reading.open!(@article)
    @expand = params[:expand] == "1"
    Claude::SummarizeArticleJob.enqueue_if_awaiting(@article)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to read_article_path(@article) }
    end
  end

  # 元の記事を開いた。画面は変えないので本文は返さない。
  # 一覧の広げた欄（from=main）では未完の判定の後も行と「記事に遷移」が残るので、開き直して測り直す（そこで読み直せるように）。
  # リーダーでは判定済みの滞在を書き換えない（読み直しは「読む」から）
  def start
    reading = Reading.find(params[:id])
    # 読み終えた判定と行き違っても判定済みの滞在を書き換えないよう、行を読み直してから見る
    reading.with_lock { params[:from] == "main" ? reading.reopen! : reading.start! }
    head :no_content
  end

  # 記事を読み終えた。判定し、その下に古い方の次の未読を開いて継ぎ足す。
  # 次の記事の行（抽選と開いた時刻）をここで作るのは、GET の描画で書き込まないため。
  # 判定済みでも同じ応答を返す。Turbo は同じ form の 2 回目の送信で 1 回目の応答を捨てるので、何も返さないと区切りも次の記事も出ずに止まる。
  # その場合は判定し直さず、次の記事が判定前なら開き直さない（滞在を測り直さない）。
  # 一覧の広げた欄から（from=main）なら次の記事は開かず（読まない記事の抽選と要約を作らない。ADR 0019）、区切りと一覧の上の 1 行・未読数だけ返す
  def advance
    @reading = Reading.includes(article: :feed).find(params[:id])
    # 判定を 1 回にするため、読み直しと判定を同じ書き込みトランザクションに入れる（同時に 2 本届くと連続数と宝箱が二重に数える）
    judged = @reading.with_lock do
      next true if @reading.returned_at.present?

      @reading.return!
      false
    end
    return advance_in_list if params[:from] == "main"

    @next_reading = next_reading_after(@reading.article, reuse_pending: judged)
    Claude::SummarizeArticleJob.enqueue_if_awaiting(@next_reading.article) if @next_reading
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @next_reading ? read_article_path(@next_reading.article) : root_path }
    end
  end

  # 全画面演出。完読済みでも開ける（戻るで一覧に帰っても結果は保持され、同じ記事を再び読めば同じ画面に来る）
  def jackpot
    @reading = Reading.includes(article: :feed).find(params[:id])
    return redirect_to root_path unless @reading.jackpot?

    @article = @reading.article
  end

  private

  def advance_in_list
    load_today_status
    @unread_count = Article.unread.count
    respond_to do |format|
      format.turbo_stream { render :advance_in_list }
      format.html { redirect_to root_path }
    end
  end

  # @return [Reading, nil] 古い方の未読が尽きたら nil
  def next_reading_after(article, reuse_pending:)
    following = Article.next_unread_after(article)
    return nil if following.nil?
    return following.reading if reuse_pending && following.reading && following.reading.returned_at.nil?

    Reading.open!(following)
  end
end
