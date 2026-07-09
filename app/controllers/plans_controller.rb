class PlansController < ApplicationController
  before_action :authenticate_client!
  layout "application"

  def index
    load_subscription

    if onboarding_complete?
      redirect_to dashboard_setting_path, notice: "プランの変更は設定画面から行えます。"
      return
    end

    @is_new_account = current_client.created_at > Subscription::TRIAL_DAYS.days.ago
  end

  def select
    plan_type = params[:plan_type]

    unless Subscription::PLAN_PRICES.key?(plan_type.to_sym)
      redirect_to plans_path, alert: "無効なプランです。"
      return
    end

    # =========================
    # TRIAL
    # =========================
    if plan_type == "trial" && current_client.created_at > Subscription::TRIAL_DAYS.days.ago

      current_client.subscriptions.where(status: :active).update_all(status: :cancelled)

      trial_end = Subscription::TRIAL_DAYS.days.from_now

      subscription = current_client.subscriptions.create!(
        plan_type: :trial,
        status: :active,
        trial_ends_at: trial_end
      )

      current_client.update!(
        subscription_plan: "trial",
        subscription_status: "active",
        trial_ends_at: trial_end
      )

      redirect_to plans_path, notice: "無料トライアルを開始しました。"
      return
    end

    redirect_to checkout_confirmation_path(plan_type: plan_type)
  end

  private

  def load_subscription
    @subscription = current_client.subscriptions.where(status: :active).order(created_at: :desc).first
    @subscription ||= current_client.subscriptions.order(created_at: :desc).first
  end

  def onboarding_complete?
    current_client.subscription_status == "active" &&
      current_client.subscriptions.where(status: :active).exists?
  end
end