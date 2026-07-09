class Client < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  validates :company, :name, :tel, :address, :url, presence: true, on: :create

  has_many :client_usage_logs, dependent: :destroy
  has_many :columns, dependent: :nullify
  has_many :service_genres, dependent: :destroy
  has_many :autonomous_content_runs, dependent: :destroy

  has_one :plan
  has_many :subscriptions, dependent: :destroy
  has_one :active_subscription, -> { where(status: :active) }, class_name: "Subscription"
  has_many :payments, dependent: :destroy


  def genre_keys
    service_genres.pluck(:key)
  end

  def full_name
    name.to_s
  end

  def client?
    true
  end

  def current_subscription
    active_subscription || subscriptions.order(created_at: :desc).first
  end

  def on_trial?
    subscription_plan == "trial" && trial_ends_at.present? && trial_ends_at > Time.current
  end

  def subscription_active?
    subscription_status == "active"
  end

  CHILD_ARTICLE_TYPES = %w[child cluster].freeze

  def plan_limits
    plan_key = current_subscription&.plan_type || subscription_plan || "trial"
    Subscription.limits_for(plan_key)
  end

  def usage_period_key
    on_trial? ? "trial" : Time.current.strftime("%Y-%m")
  end

  def usage_period_start
    if on_trial?
      anchor = trial_ends_at.presence || Time.current
      anchor - Subscription::TRIAL_DAYS.days
    else
      Time.current.beginning_of_month
    end
  end

  def usage_columns_scope
    columns.where("created_at >= ?", usage_period_start)
  end

  def pillar_usage_count
    usage_columns_scope.where(article_type: "pillar").count
  end

  def child_usage_count
    usage_columns_scope.where(article_type: CHILD_ARTICLE_TYPES).count
  end

  def current_usage_log
    client_usage_logs.find_or_create_by!(period: usage_period_key)
  end

  def title_suggestion_usage_count
    current_usage_log.title_suggestion_count
  end

  def image_generation_usage_count
    current_usage_log.image_generation_count
  end

  def can_use_api?
    plan_limits[:api_enabled]
  end

  def can_create_pillar?(count: 1)
    pillar_usage_count + count <= plan_limits[:pillar_articles]
  end

  def can_create_child?(count: 1)
    child_usage_count + count <= plan_limits[:child_articles]
  end

  def can_suggest_titles?
    title_suggestion_usage_count < plan_limits[:title_suggestions]
  end

  def max_title_suggestion_count
    (plan_limits[:title_suggestion_max_per_use] || Subscription::TITLE_SUGGESTION_BAR_MAX).to_i.clamp(1, Subscription::TITLE_SUGGESTION_BAR_MAX)
  end

  def can_generate_images?(count: 1)
    image_generation_usage_count + count <= plan_limits[:image_generations]
  end

  def can_add_genre?
    service_genres.count < plan_limits[:genre_count]
  end

  def ai_autonomous_enabled?
    plan_limits[:ai_autonomous]
  end

  DEFAULT_AUTONOMOUS_SETTINGS = {
    "notify_on" => ["cycle_complete"],
    "pause_for_approval_at" => nil,
    "default_cluster_limit" => 15
  }.freeze

  def autonomous_settings_with_defaults
    DEFAULT_AUTONOMOUS_SETTINGS.merge(autonomous_settings.is_a?(Hash) ? autonomous_settings : {})
  end

  def pause_for_child_title_approval?
    autonomous_settings_with_defaults["pause_for_approval_at"] == "child_titles"
  end

  def autonomous_notify_on
    Array(autonomous_settings_with_defaults["notify_on"])
  end

  def default_cluster_limit
    autonomous_settings_with_defaults["default_cluster_limit"].to_i.clamp(
      AutonomousContentRun::MIN_CLUSTER_LIMIT,
      AutonomousContentRun::MAX_CLUSTER_LIMIT
    )
  end

  def update_autonomous_settings!(notify_on:, pause_for_child_titles:, default_cluster_limit:)
    settings = autonomous_settings_with_defaults.dup
    settings["notify_on"] = notify_on
    settings["pause_for_approval_at"] = pause_for_child_titles ? "child_titles" : nil
    settings["default_cluster_limit"] = default_cluster_limit.to_i.clamp(
      AutonomousContentRun::MIN_CLUSTER_LIMIT,
      AutonomousContentRun::MAX_CLUSTER_LIMIT
    )
    update!(autonomous_settings: settings)
  end

  def record_title_suggestion!
    current_usage_log.increment!(:title_suggestion_count)
  end

  def record_image_generation!(count: 1)
    current_usage_log.increment!(:image_generation_count, count)
  end

  def plan_limit_message(type)
    limits = plan_limits
    case type.to_sym
    when :pillar
      "親記事の作成上限（#{limits[:pillar_articles]}記事）に達しています。プランのアップグレードをご検討ください。"
    when :child
      "子記事の作成上限（#{limits[:child_articles]}記事）に達しています。プランのアップグレードをご検討ください。"
    when :title_suggestion
      "AIタイトル提案の上限（#{limits[:title_suggestions]}回）に達しています。プランのアップグレードをご検討ください。"
    when :image_generation
      "画像生成の上限（#{limits[:image_generations]}回）に達しています。プランのアップグレードをご検討ください。"
    when :genre
      "ジャンル数の上限（#{limits[:genre_count]}個）に達しています。プランのアップグレードをご検討ください。"
    when :api
      "現在のプランではAPIを利用できません。プランのアップグレードをご検討ください。"
    when :ai_autonomous
      "AI主導生成はビジネスプラン以上で利用できます。"
    else
      "プランの利用上限に達しています。"
    end
  end

  def usage_summary
    limits = plan_limits
    {
      pillar: { used: pillar_usage_count, limit: limits[:pillar_articles] },
      child: { used: child_usage_count, limit: limits[:child_articles] },
      title_suggestions: { used: title_suggestion_usage_count, limit: limits[:title_suggestions] },
      image_generations: { used: image_generation_usage_count, limit: limits[:image_generations] },
      genres: { used: service_genres.count, limit: limits[:genre_count] },
      api_enabled: limits[:api_enabled],
      ai_autonomous: limits[:ai_autonomous]
    }
  end

  # トライアル終了時の自動アップグレード（Stripe Charge）
  def check_and_upgrade_expired_trial
    return unless subscription_plan == "trial"
    return unless trial_ends_at.present?
    return if trial_ends_at > Time.current
    return if subscription_status.in?(%w[expired cancelled])

    unless stripe_customer_id.present?
      Rails.logger.error "Client #{id} trial expired but no Stripe customer ID found"
      expire_trial_after_payment_failure!
      return nil
    end

    begin
      upgrade_plan = Subscription::POST_TRIAL_PLAN
      amount = Subscription::PLAN_PRICES[upgrade_plan]

      charge = Stripe::Charge.create(
        amount: amount,
        currency: "jpy",
        customer: stripe_customer_id,
        description: "#{Subscription::PLAN_NAMES[upgrade_plan]} subscription (trial upgrade)"
      )

      if charge.status == "succeeded"
        subscriptions.where(status: :active).update_all(status: :cancelled)

        subscription = subscriptions.create!(
          plan_type: upgrade_plan,
          status: :active,
          stripe_subscription_id: charge.id,
          trial_ends_at: nil
        )

        update!(
          subscription_plan: upgrade_plan.to_s,
          subscription_status: "active",
          trial_ends_at: nil
        )

        payments.create!(
          amount: amount,
          stripe_payment_intent_id: charge.id,
          status: "succeeded",
          description: "#{Subscription::PLAN_NAMES[upgrade_plan]} subscription (trial upgrade)"
        )

        Rails.logger.info "Client #{id} trial expired, charged #{amount} JPY via Stripe and upgraded to #{upgrade_plan} plan"
        subscription
      else
        Rails.logger.error "Client #{id} trial expired but Stripe charge failed: #{charge.failure_message}"
        expire_trial_after_payment_failure!
        nil
      end
    rescue => e
      Rails.logger.error "Error upgrading trial via Stripe for client #{id}: #{e.message}"
      expire_trial_after_payment_failure!
      nil
    end
  end

  def expire_trial_after_payment_failure!
    subscriptions.where(status: :active).update_all(status: :expired)
    update!(subscription_status: "expired")
  end

  # =========================================================================
  # 新規アカウント（トライアル期間内）であるかを判定するロジック
  # サインアップ直後などでインスタンス変数上の created_at が nil や評価前になるケースを
  # モデル層で安全にハンドリングします。
  # =========================================================================
  def new_account?
    return true if created_at.nil?

    created_at > Subscription::TRIAL_DAYS.days.ago
  end

  after_create :initialize_trial_subscription, if: :new_record?
  before_create :generate_api_key_if_blank

  private

  def generate_api_key_if_blank
    self.api_key = SecureRandom.hex(32) if api_key.blank?
  end

  def initialize_trial_subscription
    subscriptions.create!(
      plan_type: :trial,
      status: :active,
      trial_ends_at: Subscription::TRIAL_DAYS.days.from_now
    )

    update(
      subscription_plan: "trial",
      subscription_status: "active",
      trial_ends_at: Subscription::TRIAL_DAYS.days.from_now
    )
  end

end