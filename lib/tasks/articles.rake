namespace :articles do
  # 画像の列を足す前に取り込んだ記事は image_url が空のまま。カードに出る未読だけ本文取得の道に戻して拾い直す。
  # 既読・興味なしはカードに出ないので取りに行かない。og:image の無いページは何度打っても空のまま
  desc "画像の無い未読の記事の本文取得をやり直し、OGP 画像を拾い直す"
  task refetch_images: :environment do
    articles = Article.unread.where(image_url: nil)
    count = 0
    articles.find_each do |article|
      article.update!(content_fetched_at: nil)
      FetchArticleContentJob.perform_later(article)
      count += 1
    end
    puts "#{count} 本の本文取得を積みました"
  end
end
