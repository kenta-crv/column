# frozen_string_literal: true

class StripePlanValidator
  class ConfigurationError < StandardError; end

  class << self
    def purchasable_plan_types
      Subscription.purchasable_plans.keys
    end

    def validate!(plan_type = nil, currency: :jpy)
      errors = collect_errors(plan_type, currency: currency)
      return true if errors.empty?

      raise ConfigurationError, errors.join("\n")
    end

    def collect_errors(plan_type = nil, currency: :jpy)
      plan_types = plan_type.present? ? [plan_type.to_sym] : purchasable_plan_types
      currency = currency.to_sym
      errors = []

      plan_types.each do |key|
        config = Subscription.config_for(key)
        env_key = config.dig(:stripe_price_envs, currency) || config[:stripe_price_env]
        price_id = ENV[env_key.to_s]

        display_amount = Subscription.price_for(key, currency: currency)
        expected = BillingCurrency.stripe_unit_amount(display_amount, currency)

        if price_id.blank?
          errors << "#{env_key} が未設定です（#{config[:name]} #{Subscription.format_price(key, currency: currency)}/月）"
          next
        end

        stripe_price = Stripe::Price.retrieve(price_id)
        actual = stripe_price.unit_amount.to_i

        if actual != expected
          errors << "#{env_key} の金額が不一致: Stripe=#{actual} / カタログ=#{expected}（#{config[:name]} / #{currency}）"
        end

        if stripe_price.currency.to_s != currency.to_s
          errors << "#{env_key} の通貨が不一致: Stripe=#{stripe_price.currency} / 期待=#{currency}"
        end

        if stripe_price.recurring&.interval != "month"
          errors << "#{env_key} は月額サブスクリプションではありません"
        end
      rescue Stripe::StripeError => e
        errors << "#{env_key} の取得に失敗: #{e.message}"
      end

      errors
    end

    def report
      lines = ["Drafity Stripe プラン整合性チェック", ""]

      purchasable_plan_types.each do |key|
        BillingCurrency::CURRENCIES.each do |currency|
          config = Subscription.config_for(key)
          env_key = config.dig(:stripe_price_envs, currency) || config[:stripe_price_env]
          price_id = ENV[env_key.to_s]
          catalog_amount = BillingCurrency.stripe_unit_amount(Subscription.price_for(key, currency: currency), currency)

          if price_id.blank?
            lines << "[MISSING] #{key}/#{currency}: #{env_key} 未設定（期待 #{catalog_amount}）"
            next
          end

          begin
            stripe_price = Stripe::Price.retrieve(price_id)
            actual = stripe_price.unit_amount.to_i
            status = actual == catalog_amount ? "OK" : "MISMATCH"
            lines << "[#{status}] #{key}/#{currency}: #{price_id} => Stripe #{actual} / カタログ #{catalog_amount}"
          rescue Stripe::StripeError => e
            lines << "[ERROR] #{key}/#{currency}: #{price_id} => #{e.message}"
          end
        end
      end

      lines.join("\n")
    end

    def plan_type_for_price_id(price_id)
      return nil if price_id.blank?

      purchasable_plan_types.find do |key|
        config = Subscription.config_for(key)
        envs = config[:stripe_price_envs]&.values || [config[:stripe_price_env]]
        envs.compact.any? { |env_key| ENV[env_key] == price_id }
      end&.to_s
    end
  end
end
