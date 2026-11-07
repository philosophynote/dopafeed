Rails.application.routes.draw do
  resource :session
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # PWA の manifest と service worker（app/views/pwa/）。ホーム画面に追加する前に読まれるので認証の外（Rails::PwaController）
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # ログイン後の着地点（after_authentication_url が root_url を使う）
  root "main#show"
  resource :learning, only: :show, controller: :learning
  # ホーム画面に追加する手順と、通知・バッジの入口
  resource :install, only: :show, controller: :install
  # 今日のゴール（宝箱）。描くだけで書き込まない
  resource :daily_goal, only: :show
  resources :articles, only: [] do
    resource :reading, only: :create
    # アプリ内のリーダー。描くだけで書き込まない（行は「読む」と advance が作る）
    get :read, on: :member
    # 読まずに片付ける（POST）と、その取り消し（DELETE）
    resource :dismissal, only: %i[create destroy]
  end
  resources :readings, only: [] do
    # 「記事を開く」を押した。滞在を数え始める時刻を記録するだけ
    post :start, on: :member
    post :advance, on: :member
    get :jackpot, on: :member
  end
end
