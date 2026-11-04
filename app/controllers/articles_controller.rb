# アプリ内で記事の本文を読む。「読む」で行（抽選と開いた時刻）ができた記事だけを開き、2 本目からは末尾で継ぎ足す（ReadingsController#advance）
class ArticlesController < ApplicationController
  def read
    @article = Article.includes(:feed).find(params[:id])
    @reading = @article.reading
    redirect_to root_path if @reading.nil?
  end
end
