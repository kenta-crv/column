Rails.application.routes.draw do
  devise_for :admins, controllers: {
    sessions: 'admins/sessions',
    registrations: 'admins/registrations'
  }

  require 'sidekiq/web'
  authenticate :admin do
    mount Sidekiq::Web, at: "/sidekiq"
  end

  # --- 1. 最優先：公開用マルチドメイン対応ルート ---
  # resourcesより先に定義することで、URL生成時にこちらが優先されます
  scope ':genre/columns', constraints: {
    genre: Regexp.new(GenreRegistry::GENRES.keys.join("|"))
  } do
    get '/',    to: 'columns#index', as: :columns_index
    get '/:id', to: 'columns#show',  as: :columns_show
  end

  # --- 2. 管理機能・共通ルート ---
  post 'columns/generate_from_selected', to: 'columns#generate_from_selected'
  post 'columns/bulk_update_drafts', to: 'columns#bulk_update_drafts'

  resources :columns do
    collection do
      get :draft
      get :check_bulk_image_count
      post :bulk_generate_images
      post :generate_gemini
      post :generate_pillar
      post :generate_from_selected
      match 'bulk_update_drafts', via: [:post, :patch]
    end

    member do
      post :generate_from_pillar
      patch :remove_image
      post :generate_title
      patch :approve
    end
  end

  root to: 'columns#index'

  # 標準の /columns パスへのアクセスは制限
  get '/columns', to: ->(env) { [404, {}, ['Not Found']] }

  # static pages
  #get 'security',     to: 'pages#security'
  #get 'short',        to: 'pages#short'
  #get 'vender',       to: 'pages#vender'
  #get 'recruit',      to: 'pages#recruit'
  #get 'bpo',          to: 'pages#bpo'
  #get 'pest',         to: 'pages#pest'
  #get 'ads',          to: 'pages#ads'
  get '/pages/cargo',          to: 'pages#cargo'
  get '/pages/human',          to: 'pages#human'
  get '/pages/event',          to: 'pages#event'
  get '/pages/logistic',          to: 'pages#logistic'

  get 'draft/progress', to: 'draft#progress'
  resources :contracts
end