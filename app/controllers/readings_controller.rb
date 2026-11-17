class ReadingsController < ApplicationController
  include TodayStatus

  def create
    @article = Article.find(params[:article_id])
    @reading = Reading.open!(@article)
    Claude::SummarizeArticleJob.enqueue_if_awaiting(@article)
    JudgeArticleJob.enqueue_if_awaiting(@article)
    return open_reader unless params[:expand] == "1"

    respond_to do |format|
      format.turbo_stream
      format.html { open_reader }
    end
  end

  def start
    reading = Reading.find(params[:id])
    # 判定と行き違っても滞在を書き換えないよう、行を読み直してから判断する。
    reading.with_lock { params[:from] == "main" ? reading.reopen! : reading.start! }
    head :no_content
  end

  # GET の描画で書き込まないよう、次の記事の行もここで作る。
  # Turbo は二重送信で最初の応答を捨てるため、判定済みでも同じ応答を返さないと流れが止まる。
  def advance
    @reading = Reading.includes(article: :feed).find(params[:id])
    # 同時に 2 本届いても連続数と宝箱を二重に数えないよう、読み直しと判定を同じトランザクションに入れる。
    judged = @reading.with_lock do
      next true if @reading.returned_at.present?

      @reading.return!
      false
    end
    return advance_in_list if params[:from] == "main"

    @next_reading = next_reading_after(@reading.article, reuse_pending: judged)
    if @next_reading
      Claude::SummarizeArticleJob.enqueue_if_awaiting(@next_reading.article)
      JudgeArticleJob.enqueue_if_awaiting(@next_reading.article)
    end
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @next_reading ? read_article_path(@next_reading.article) : root_path }
    end
  end

  private

  # 帯を回すのは抽選した直後の 1 回だけ。GET の側では行が今できたのか分からないので、flash で渡す。
  def open_reader
    flash[:drawn] = true if @reading.previously_new_record?
    redirect_to read_article_path(@article), status: :see_other
  end

  def advance_in_list
    load_today_status
    @unread_count = Article.unread.count
    respond_to do |format|
      format.turbo_stream { render :advance_in_list }
      format.html { redirect_to root_path }
    end
  end

  def next_reading_after(article, reuse_pending:)
    following = Article.next_unread_after(article)
    return nil if following.nil?
    return following.reading if reuse_pending && following.reading && following.reading.returned_at.nil?

    Reading.open!(following)
  end
end
