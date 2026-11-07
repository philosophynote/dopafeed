# 記事のカードを出し、元サイトを開く入口にする。「読む」で行（抽選と開いた時刻）ができた記事だけを出し、2 本目からは読み終えたときに継ぎ足す（ReadingsController#advance）
class ArticlesController < ApplicationController
  def read
    @article = Article.includes(:feed).find(params[:id])
    @reading = @article.reading
    redirect_to root_path if @reading.nil?
  end
end
