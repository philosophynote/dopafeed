// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// ホーム画面に追加できるための登録。失敗しても画面は動くので黙って続ける
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/service-worker").catch(() => {})
}
