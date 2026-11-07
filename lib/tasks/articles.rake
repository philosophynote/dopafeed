namespace :articles do
  # 本文取得を済ませた記事の image_url を、本文取得をやり直して埋める。読む前の未読だけ取りに行く（読み終えた・興味なしの記事に通信を使わない）。
  # 取得待ちの記事はいずれ Job が拾うので積まない。og:image の無いページは何度打っても空のまま
  desc "画像の無い未読の記事の本文取得をやり直し、OGP 画像を拾い直す"
  task refetch_images: :environment do
    articles = Article.unread.where(image_url: nil).where.not(content_fetched_at: nil)
    count = 0
    articles.find_each do |article|
      article.update!(content_fetched_at: nil)
      FetchArticleContentJob.perform_later(article)
      count += 1
    end
    puts "#{count} 本の本文取得を積みました"
  end
end
