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
  resources :articles, only: [] do
    resource :reading, only: :create
  end
  # return は Ruby の予約語なのでアクション名は finish。
  # id を取らないのは、戻り先が「読む」を押す前に描いた文書のままで、どの行を開いたか文書が知らないから
  resources :readings, only: :show do
    post :return, on: :collection, action: :finish
  end
end
