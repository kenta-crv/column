class CheckoutController < ApplicationController
  before_action :authenticate_client!

  def confirmation
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"

    @plan_type = params[:plan_type]
    @billing_currency = resolve_billing_currency

    if @plan_type.blank?
      redirect_to plans_path_for_locale, alert: t("drafity.auth.select_plan", default: "プランを選択してください。")
      return
    end

    unless Subscription::PLANS.key?(@plan_type.to_sym)
      redirect_to plans_path_for_locale, alert: t("drafity.auth.invalid_plan")
      return
    end

    config = Subscription.plan_config(@plan_type)
    unless config[:purchasable] || @plan_type == "trial"
      redirect_to plans_path_for_locale, alert: t("drafity.auth.invalid_plan")
      return
    end

    @plan_config = config
    @amount = Subscription.price_for(@plan_type, currency: @billing_currency)
    @formatted_amount = Subscription.format_price(@plan_type, currency: @billing_currency)

    if @plan_type == "trial"
      @description = t("drafity.auth.trial_description", days: Subscription::TRIAL_DAYS, default: "無料トライアル (%{days}日間)")
      @amount = 0
      @formatted_amount = Subscription.format_price(:trial, currency: @billing_currency)

      if current_client.new_account? == false || current_client.subscriptions.where(plan_type: :trial).exists?
        redirect_to plans_path_for_locale, alert: t("drafity.auth.trial_new_only")
        return
      end
    else
      @description = I18n.locale.to_s == "en" ? (@plan_config[:name_en] || @plan_config[:name]) : @plan_config[:name]
      @intro_discount = (@plan_type.to_s == "standard")
    end

    @subscription = Subscription.new(plan_type: @plan_type)
  end

  def create
    plan_type = params[:plan_type]
    @billing_currency = resolve_billing_currency

    Rails.logger.info("[Checkout#create] plan_type=#{plan_type} currency=#{@billing_currency}")

    if plan_type.blank?
      redirect_to plans_path_for_locale, alert: t("drafity.auth.select_plan", default: "プランを選択してください。")
      return
    end

    unless Subscription::PLANS.key?(plan_type.to_sym)
      redirect_to plans_path_for_locale, alert: t("drafity.auth.invalid_plan")
      return
    end

    if plan_type == "trial"
      process_trial_checkout!
      return
    end

    begin
      process_subscription_payment(plan_type)
    rescue Stripe::CardError => e
      Rails.logger.error("[Stripe Card Error] #{e.class} #{e.message}")
      redirect_to checkout_confirmation_path(plan_type: plan_type), alert: t("drafity.auth.card_error", message: e.message, default: "カード決済に失敗しました: %{message}")
    rescue Stripe::StripeError => e
      Rails.logger.error("[Stripe API Error] #{e.class} #{e.message}")
      redirect_to checkout_confirmation_path(plan_type: plan_type), alert: t("drafity.auth.stripe_error", message: e.message, default: "Stripe決済エラー: %{message}")
    rescue => e
      Rails.logger.error("[Checkout Error] #{e.class} #{e.message}")
      redirect_to checkout_confirmation_path(plan_type: plan_type), alert: t("drafity.auth.checkout_error", default: "決済処理中にエラーが発生しました。")
    end
  end

  def success
    session_id = params[:session_id]

    if session_id.blank?
      @subscription = current_client.subscriptions.order(created_at: :desc).first
      @payment = current_client.payments.order(created_at: :desc).first
      @amount = @payment&.amount || 0
      @invoice_id = @payment&.stripe_payment_intent_id
      @plan_name = @subscription&.plan_name || t("drafity.auth.plan_fallback", default: "プラン")
      return
    end

    begin
      @session = Stripe::Checkout::Session.retrieve(session_id)

      @amount = @session.amount_total
      @invoice_id = @session.invoice || @session.payment_intent

      @plan_type = @session.metadata["plan_type"]
      @payment_type = @session.metadata["payment_type"]

      if @payment_type == "subscription" && @plan_type.present?
        @plan_name = Subscription::PLAN_NAMES[@plan_type.to_sym] rescue @plan_type.to_s
      else
        @plan_name = t("drafity.auth.payment_fallback", default: "決済")
      end

      if @session.payment_status == "paid"
        if @payment_type == "subscription" && @plan_type.present? && @session.subscription.present?
          Subscription.transaction do
            sub = current_client.subscriptions.find_or_initialize_by(stripe_subscription_id: @session.subscription)
            current_client.subscriptions.where.not(id: sub.id).update_all(status: :cancelled)

            sub.update!(plan_type: @plan_type, status: :active, trial_ends_at: nil)
            current_client.update!(
              subscription_plan: @plan_type,
              subscription_status: "active",
              trial_ends_at: nil
            )
          end

          @subscription = current_client.subscriptions.find_by(stripe_subscription_id: @session.subscription)
        end
      end

      @payment = current_client.payments.find_by(stripe_payment_intent_id: @invoice_id) || current_client.payments.order(created_at: :desc).first

    rescue Stripe::StripeError => e
      Rails.logger.error("[Stripe Success Retrieve Error] #{e.message}")
      @plan_name = t("drafity.auth.plan_fallback", default: "プラン")
      @amount = 0
      @invoice_id = "N/A"
    end
  end

  def cancel
    redirect_to plans_path_for_locale, alert: t("drafity.auth.checkout_cancelled", default: "決済がキャンセルされました。")
  end

  private

  def resolve_billing_currency
    BillingCurrency.resolve(
      locale: I18n.locale,
      accept_language: request.headers["Accept-Language"]
    )
  end

  def process_trial_checkout!
    unless current_client.new_account?
      redirect_to plans_path_for_locale, alert: t("drafity.auth.trial_new_only")
      return
    end

    if current_client.subscriptions.where(plan_type: :trial).exists?
      redirect_to plans_path_for_locale, alert: t("drafity.auth.trial_new_only")
      return
    end

    current_client.initialize_trial_subscription!
    redirect_to dashboard_root_path, notice: t("drafity.auth.trial_started", days: Subscription::TRIAL_DAYS, default: "%{days}日間の無料トライアルを開始しました。")
  end

  def process_subscription_payment(plan_type)
    config = Subscription.plan_config(plan_type)
    unless config&.dig(:purchasable)
      redirect_to plans_path_for_locale, alert: t("drafity.auth.invalid_plan")
      return
    end

    currency = @billing_currency || resolve_billing_currency
    stripe_price_id = Subscription.stripe_price_id_for(plan_type, currency: currency)

    unless stripe_price_id.present?
      env_key = Subscription.stripe_price_env_key(plan_type, currency: currency)
      redirect_to plans_path_for_locale, alert: t("drafity.auth.stripe_price_missing", key: env_key, default: "Stripe Price ID が未設定です（%{key}）。")
      return
    end

    begin
      StripePlanValidator.validate!(plan_type, currency: currency)
    rescue StripePlanValidator::ConfigurationError => e
      Rails.logger.error("[Checkout] Stripe plan mismatch: #{e.message}")
      redirect_to plans_path_for_locale, alert: t("drafity.auth.stripe_mismatch", default: "Stripeの料金設定がプラン定義と一致しません。管理者に連絡してください。")
      return
    end

    customer = ensure_stripe_customer!

    session_params = {
      mode: "subscription",
      customer: customer.id,
      payment_method_types: ["card"],
      line_items: [{ price: stripe_price_id, quantity: 1 }],
      locale: checkout_locale,
      metadata: {
        client_id: current_client.id,
        plan_type: plan_type.to_s,
        payment_type: "subscription",
        billing_currency: currency.to_s
      },
      success_url: "#{checkout_success_url}?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: checkout_cancel_url
    }

    if plan_type.to_s == "standard"
      coupon_id = Subscription.intro_coupon_id_for(:standard)
      session_params[:discounts] = [{ coupon: coupon_id }] if coupon_id.present?
    end

    session = Stripe::Checkout::Session.create(session_params)
    redirect_to session.url, allow_other_host: true
  end

  def checkout_locale
    I18n.locale.to_s == "en" ? "en" : "ja"
  end

  def ensure_stripe_customer!
    if current_client.stripe_customer_id.present?
      Stripe::Customer.retrieve(current_client.stripe_customer_id)
    else
      customer = Stripe::Customer.create(email: current_client.email, metadata: { client_id: current_client.id })
      current_client.update!(stripe_customer_id: customer.id)
      customer
    end
  end
end
