Rails.application.routes.draw do
  devise_for :admins, controllers: {
    sessions: "admins/sessions",
    registrations: "admins/registrations",
    passwords: "admins/passwords"
  }
  
  devise_for :clients, controllers: {
    sessions: "clients/sessions",
    registrations: "clients/registrations",
    passwords: "clients/passwords"
  }

  # --- 管理画面を /dashboard 配下に完全移行 ---
  namespace :dashboard do
    resources :columns do
      collection do
        get :drafts
        get :export
        post :bulk_generate_images
        get :check_bulk_image_count
      end

      member do
        patch :remove_image
      end
    end

    root to: "columns#index"
    get 'setting', to: 'dashboards#setting'
    get 'management', to: 'dashboards#management'

    resource :subscription, only: [:show, :update] do
      get :cancel_confirm
      post :cancel
    end
    resources :notifications
  end

  require 'sidekiq/web'
  authenticate :admin do
    mount Sidekiq::Web, at: "/sidekiq"
  end

  # --- 1. 最優先：公開用マルチドメイン対応ルート ---
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

  get '/columns', to: ->(env) { [404, {}, ['Not Found']] }

  get '/tops',    to: 'tops#index'

  get '/pages/cargo',    to: 'pages#cargo'
  get '/pages/human',    to: 'pages#human'
  get '/pages/event',    to: 'pages#event'
  get '/pages/cleaning',    to: 'pages#cleaning'
  get '/pages/logistic', to: 'pages#logistic'

  get 'draft/progress', to: 'draft#progress'
  resources :contracts

  get 'checkout/confirmation', to: 'checkout#confirmation', as: :checkout_confirmation
  post 'checkout/create', to: 'checkout#create', as: :checkout_create
  get 'checkout/success', to: 'checkout#success', as: :checkout_success
  get 'checkout/cancel', to: 'checkout#cancel', as: :checkout_cancel

  post 'stripe/webhook', to: 'stripe_webhooks#create'
  get 'plans', to: 'plans#index', as: :plans
  post 'plans/select', to: 'plans#select', as: :select_plan


  get '/unsubscribe/:token', to: 'unsubscribes#show', as: :unsubscribe
  post '/webhooks/stripe', to: 'webhooks#stripe'
  get '/l/:token', to: 'click_tracking#redirect', as: :click_tracking
end