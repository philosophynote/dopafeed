namespace :articles do
  # 取得待ちには Job が既にあるので積み直さない。og:image の無いページは再取得しても空のまま。
  # 積めなかったら印を戻さないと、取得待ちに見えて誰も積み直せない。
  desc "画像の無い未読の記事の本文取得をやり直し、OGP 画像を拾い直す"
  task refetch_images: :environment do
    articles = Article.unread.where(image_url: nil).where.not(content_fetched_at: nil)
    count = 0
    articles.find_each do |article|
      fetched_at = article.content_fetched_at
      article.update!(content_fetched_at: nil)
      begin
        FetchArticleContentJob.perform_later(article) || raise(ActiveJob::EnqueueError, "積めませんでした (#{article.id})")
      rescue StandardError
        article.update!(content_fetched_at: fetched_at)
        raise
      end
      count += 1
    end
    puts "#{count} 本の本文取得を積みました"
  end
end
