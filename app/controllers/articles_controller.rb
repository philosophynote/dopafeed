# 記事のカードを出し、元サイトを開く入口にする。「読む」で行（抽選と開いた時刻）ができた記事だけを出し、2 本目からは読み終えたときに継ぎ足す（ReadingsController#advance）
class ArticlesController < ApplicationController
  def read
    @article = Article.includes(:feed).find(params[:id])
    @reading = @article.reading
    return redirect_to root_path if @reading.nil?

    # 開くたびに要約待ちなら積み直す。予算切れで捨てた記事は、翌日に開き直しても誰も積まないため（要約済み・積み済みなら Job が何もしない）
    Claude::SummarizeArticleJob.enqueue_if_awaiting(@article)
  end

  def summary
    render partial: "articles/summary", locals: { article: Article.find(params[:id]) }
  end
end
