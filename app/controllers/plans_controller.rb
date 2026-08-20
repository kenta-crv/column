class PlansController < ApplicationController
  before_action :authenticate_client!

  def index
    @is_new_account = current_client.new_account?

    # =========================
    # 現在のサブスク（必ず実データ）
    # =========================
    @subscription = current_client.subscriptions
                                 .where(status: :active)
                                 .order(created_at: :desc)
                                 .first

    # fallback（念のため）
    if @subscription.nil?
      @subscription = current_client.subscriptions
                                   .order(created_at: :desc)
                                   .first
    end

    # =========================
    # 支払い履歴
    # =========================
    @payments = current_client.payments
                              .order(created_at: :desc)
                              .limit(50)
  end

  def select
    plan_type = params[:plan_type]
    config = Subscription.plan_config(plan_type)

    unless config
      redirect_to plans_path_for_locale, alert: t("drafity.auth.invalid_plan")
      return
    end

    if plan_type == "trial"
      unless current_client.new_account? && !current_client.subscriptions.exists?(plan_type: :trial)
        redirect_to plans_path_for_locale, alert: t("drafity.auth.trial_new_only")
        return
      end

      current_client.initialize_trial_subscription!
      mark_yahoo_trial_conversion!
      redirect_to dashboard_root_path, notice: t("drafity.auth.trial_started", days: Subscription::TRIAL_DAYS, default: "無料トライアルを開始しました。")
      return
    end

    unless config[:checkout_selectable] || config[:purchasable]
      redirect_to plans_path_for_locale, alert: t("drafity.auth.invalid_plan")
      return
    end

    redirect_to checkout_confirmation_path(plan_type: plan_type)
  end
end