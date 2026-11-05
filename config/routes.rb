Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # ログイン後の着地点（after_authentication_url が root_url を使う）
  root "main#show"
  resource :learning, only: :show, controller: :learning
  # 今日のゴール（宝箱）。描くだけで書き込まない（達成の行は goal 本目の判定が作る）
  resource :daily_goal, only: :show
  resources :articles, only: [] do
    resource :reading, only: :create
    # アプリ内のリーダー。描くだけで書き込まない（行は「読む」と advance が作る）
    get :read, on: :member
  end
  resources :readings, only: [] do
    # 「記事を開く」を押した。滞在を数え始める時刻を記録するだけ
    post :start, on: :member
    post :advance, on: :member
    get :jackpot, on: :member
  end
end
