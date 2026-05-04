Rails.application.routes.draw do
  devise_for :admins, controllers: {
    sessions: 'admins/sessions',
    registrations: 'admins/registrations'
  }

  require 'sidekiq/web'
  authenticate :admin do
    mount Sidekiq::Web, at: "/sidekiq"
  end

  post 'columns/generate_from_selected', to: 'columns#generate_from_selected'
  post 'columns/bulk_update_drafts', to: 'columns#bulk_update_drafts'

  resources :columns do
    collection do
      get :draft
      post :generate_gemini
      post :generate_pillar
      post :generate_from_selected
      match 'bulk_update_drafts', via: [:post, :patch]
    end

    member do
      post :generate_from_pillar
      post :generate_title
      patch :approve
    end
  end

  root to: 'columns#index'

  get '/columns', to: ->(env) { [404, {}, ['Not Found']] }

  # genreスコープ（メイン表示）
  scope ':genre/columns', constraints: {
    genre: Regexp.new(GenreRegistry::GENRES.keys.join("|"))
  } do
    get '/',    to: 'columns#index', as: :columns_index
    get '/:id', to: 'columns#show',  as: :columns_show
  end

  # static pages
  get 'construction', to: 'pages#construction'
  get 'security',     to: 'pages#security'
  get 'short',        to: 'pages#short'
  get 'vender',       to: 'pages#vender'
  get 'recruit',      to: 'pages#recruit'
  get 'bpo',          to: 'pages#bpo'
  get 'pest',         to: 'pages#pest'
  get 'ads',          to: 'pages#ads'

  get 'draft/progress', to: 'draft#progress'
  resources :contracts
end