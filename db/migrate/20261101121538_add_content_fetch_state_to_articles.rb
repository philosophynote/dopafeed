# 記事ページの本文取得（ArticleContentFetcher、Unit 3b）の状態。
# content_fetched_at は試行時刻（nil なら未取得。Job の冪等の鍵）、content_error は失敗の文言（nil なら成功）
class AddContentFetchStateToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :content_fetched_at, :datetime
    add_column :articles, :content_error, :string
  end
end
