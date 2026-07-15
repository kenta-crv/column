# Sidekiq は AI主導生成（autonomous キュー）専用。
# 通常の記事生成は ActiveJob :async + perform_now のまま。
redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end
