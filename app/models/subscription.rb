class Subscription < ApplicationRecord
  belongs_to :client

  # 1. enum の定義に starter が不足していたため追加
  enum plan_type: { trial: "trial", starter: "starter", standard: "standard", enterprise: "enterprise" }
  enum status: { active: "active", cancelled: "cancelled", expired: "expired" }

  validates :plan_type, presence: true
  validates :status, presence: true

  validates :stripe_subscription_id,
            uniqueness: true,
            allow_nil: true

  # 2. カンマのタイポ（starterの後ろ）を修正
  PLAN_NAMES = {
    trial: "トライアルプラン",
    starter: "スタータープラン",
    standard: "スタンダードプラン",
    enterprise: "エンタープライズプラン"
  }.freeze

  PLAN_PRICES = {
    trial: 0,
    starter: 29_800,
    standard: 49_800,
    enterprise: 98_000
  }.freeze

  DELIVERY_COST = 50

  PLAN_DELIVERY_LIMITS = {
    trial: 3, # 3. コメントにある「トライアルなら1000件」と乖離があるため注意（※後述）
    starter: 25,
    standard: 50,
    enterprise: 120
  }.freeze

  TRIAL_DAYS = 10

  def plan_name
    PLAN_NAMES[plan_type.to_sym]
  end

  def price
    PLAN_PRICES[plan_type.to_sym] || 0
  end

  def delivery_limit
    PLAN_DELIVERY_LIMITS[plan_type.to_sym] || 0
  end

  def unlimited?
    delivery_limit == Float::INFINITY
  end

  # 今月これまでに送信した累積件数を含めて、上限を超えないか正しく検証
  def can_send_delivery?(count)
    return true if unlimited?
    (client.monthly_sent_count + count) <= delivery_limit
  end

  def trial?
    plan_type == "trial"
  end

  def trial_active?
    trial? && trial_ends_at.present? && trial_ends_at > Time.current
  end

  def trial_expired?
    trial? && trial_ends_at.present? && trial_ends_at <= Time.current
  end

  # トライアル期間終了時のアップグレード先を「enterprise（98,000円）」に完全統一
  def expire_trial_and_upgrade!
    return unless trial?
    return if trial_ends_at.blank?
    return if trial_ends_at > Time.current
    return if status != "active"

    transaction do
      update!(status: :expired)

      client.subscriptions.where(status: :active).update_all(status: :cancelled)

      client.subscriptions.create!(
        plan_type: :enterprise,
        status: :active
      )

      client.update!(
        subscription_plan: "enterprise",
        subscription_status: "active",
        trial_ends_at: nil
      )
    end
  end
end