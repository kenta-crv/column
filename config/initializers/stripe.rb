# Payjp.api_key = Rails.application.credentials.dig(:payjp, :secret_key) || ENV['PAYJP_SECRET_KEY']
#
# NOTE:
# - Never use ENV.fetch here; boot-time KeyError can break unrelated tasks
#   (deploy checks, db tasks, assets, etc.) when process env differs.
# - Read from multiple sources so production is resilient to env-loading differences.
stripe_secret_key =
  ENV["STRIPE_SECRET_KEY"].presence ||
  Rails.application.credentials.dig(:stripe, :secret_key).presence ||
  Rails.application.credentials.dig(Rails.env.to_sym, :stripe, :secret_key).presence

if stripe_secret_key.present?
  Stripe.api_key = stripe_secret_key
else
  Rails.logger.warn("[Stripe] STRIPE_SECRET_KEY is not configured. Stripe features will fail until key is set.")
end