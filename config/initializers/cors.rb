Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # ローカル環境のあらゆるポートからのリクエストを許可
    origins '*', /localhost:\d+/, /127.0.0.1:\d+/

    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      expose: ['X-API-Key'],
      credentials: false
  end
end