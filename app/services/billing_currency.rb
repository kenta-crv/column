# frozen_string_literal: true

# ja → JPY / それ以外 → USD
class BillingCurrency
  CURRENCIES = %i[jpy usd].freeze

  class << self
    def resolve(locale:, accept_language: nil)
      loc = locale.to_s.downcase
      return :jpy if loc.start_with?("ja")

      :usd
    end

    def symbol(currency)
      currency.to_sym == :usd ? "$" : "¥"
    end

    # Stripe: JPYは整数円、USDはminor units（cents）
    def stripe_unit_amount(display_amount, currency)
      currency.to_sym == :jpy ? display_amount.to_i : (display_amount.to_d * 100).to_i
    end
  end
end
