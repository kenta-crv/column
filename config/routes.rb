Rails.application.routes.draw do
  get "/robots.txt", to: "robots#show"
  get "/sitemap.xml", to: "sitemaps#show"

  devise_for :admins, skip: [:registrations], controllers: {
    sessions: "admins/sessions",
    passwords: "admins/passwords"
  }
  
  devise_for :clients, controllers: {
    sessions: "clients/sessions",
    registrations: "clients/registrations",
    passwords: "clients/passwords"
  }

  # --- 管理画面を /dashboard 配下に完全移行 ---
  namespace :dashboard do
    get 'setting', to: 'columns#setting'
    get 'management', to: 'columns#management'
    
    get 'api_settings', to: 'clients#my_api_settings'
    patch 'api_settings', to: 'clients#update_my_api_settings'

    resources :columns do
      collection do
        get :drafts
        get :export
        get :image_generation
        get :generation_status
        post :bulk_generate_images
        get :check_bulk_image_count
        
        # JS側の GET "/dashboard/columns/suggest" を、コントローラーの suggest_titles メソッドへ繋ぐ
        get :suggest, to: 'columns#suggest_titles'
        
        post :create_from_suggestion
        post :bulk_create_from_suggestions
      end

      member do
        patch :remove_image
        patch :stop_generation
      end
    end

    resources :clients do
      member do
        get :api_settings
        patch :update_api_settings
      end
    end

    resources :service_genres, except: [:show] do
      collection do
        post :suggest_sub_categories
      end
    end

    root to: "columns#index"

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
    genre: Regexp.new(GenreRegistry.genre_keys.join("|"))
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
      post :generate_pillar
      post :generate_from_selected
      match 'bulk_update_drafts', via: [:post, :patch]
    end

    member do
      patch :remove_image
      post :generate_title
      patch :approve
    end
  end

  root to: 'tops#index'

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

  get 'plans', to: 'plans#index', as: :plans
  post 'plans/select', to: 'plans#select', as: :select_plan

  get '/unsubscribe/:token', to: 'unsubscribes#show', as: :unsubscribe
  post '/webhooks/stripe', to: 'webhooks#stripe'
  get '/l/:token', to: 'click_tracking#redirect', as: :click_tracking

  # API for article distribution
  namespace :api do
    namespace :v1 do
      resources :articles, only: [:index] do
        collection do
          post :render_html
        end
      end
      get 'articles/:code', to: 'articles#show', as: :article
    end
  end
end