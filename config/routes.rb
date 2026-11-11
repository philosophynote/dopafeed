Rails.application.routes.draw do
  resource :session

  get "up" => "rails/health#show", as: :rails_health_check

  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "main#show"
  resources :feeds, only: %i[index new create edit update destroy]
  resource :learning, only: :show, controller: :learning
  resource :install, only: :show, controller: :install
  resource :push_subscription, only: [ :create, :destroy ]
  resource :daily_goal, only: :show
  resource :saved, only: :show, controller: :saved
  # 手に入れたカードの図鑑。描くだけで書き込まない
  resource :collection, only: :show, controller: :collection
  resources :articles, only: [] do
    resource :reading, only: :create
    get :read, on: :member
    get :summary, on: :member
    resource :dismissal, only: %i[create destroy]
    resource :bookmark, only: %i[create destroy]
  end
  resources :readings, only: [] do
    post :start, on: :member
    post :advance, on: :member
    get :jackpot, on: :member
  end
end
