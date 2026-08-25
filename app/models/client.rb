class Client < ApplicationRecord
  LOCALES = %w[ja en].freeze

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: %i[google_oauth2 microsoft_graph]

  has_many :client_usage_logs, dependent: :destroy
  has_many :columns, dependent: :nullify
  has_many :service_genres, dependent: :destroy
  has_many :autonomous_content_runs, dependent: :destroy

  has_one :plan
  has_many :subscriptions, dependent: :destroy
  has_one :active_subscription, -> { where(status: :active) }, class_name: "Subscription"
  has_many :payments, dependent: :destroy

  validates :preferred_locale, inclusion: { in: LOCALES }

  def self.from_omniauth(auth, preferred_locale: "ja")
    email = auth.info.email.to_s.downcase.presence
    raise ArgumentError, "OAuth email missing" if email.blank?

    client = find_by(provider: auth.provider, uid: auth.uid)
    return client if client

    client = find_by(email: email)
    if client
      client.update!(provider: auth.provider, uid: auth.uid)
      client.name = auth.info.name if client.name.blank? && auth.info.name.present?
      client.preferred_locale = preferred_locale if client.preferred_locale.blank?
      client.save! if client.changed?
      return client
    end

    create!(
      email: email,
      password: Devise.friendly_token[0, 20],
      name: auth.info.name,
      provider: auth.provider,
      uid: auth.uid,
      preferred_locale: preferred_locale
    )
  end

  def password_required?
    return false if provider.present?

    super
  end

  def ui_locale
    value = self[:preferred_locale].presence || "ja"
    (LOCALES.include?(value) ? value : "ja").to_sym
  end

  def send_devise_notification(notification, *args)
    I18n.with_locale(ui_locale) { super }
  end

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

  def update_company_name(value)
    name = value.to_s.strip
    return false if name.blank?
    return true if company == name

    update(company: name)
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
    reconcile_article_creation_usage_if_drifted!
    current_usage_log.pillar_created_count
  end

  def child_usage_count
    reconcile_article_creation_usage_if_drifted!
    current_usage_log.child_created_count
  end

  def actual_pillar_count_in_period
    pillar_slots_used
  end

  def actual_child_count_in_period
    child_slots_used
  end

  def pillar_slots_used(excluding: nil)
    scope = usage_columns_scope.where(parent_id: nil).where.not(article_type: CHILD_ARTICLE_TYPES)
    scope = scope.where.not(id: excluding.id) if excluding&.persisted?
    scope.count
  end

  def child_slots_used(excluding: nil)
    scope = usage_columns_scope.where(
      "article_type IN (:types) OR parent_id IS NOT NULL",
      types: CHILD_ARTICLE_TYPES
    ).where.not(article_type: "pillar")
    scope = scope.where.not(id: excluding.id) if excluding&.persisted?
    scope.count
  end

  def reconcile_article_creation_usage_if_drifted!(actual_pillar: nil, actual_child: nil)
    actual_pillar = actual_pillar_count_in_period if actual_pillar.nil?
    actual_child = actual_child_count_in_period if actual_child.nil?
    log = current_usage_log
    return if log.pillar_created_count >= actual_pillar && log.child_created_count >= actual_child

    log.update_columns(
      pillar_created_count: [log.pillar_created_count, actual_pillar].max,
      child_created_count: [log.child_created_count, actual_child].max
    )
  end

  def record_pillar_creation!(count: 1)
    current_usage_log.increment!(:pillar_created_count, count)
  end

  def record_child_creation!(count: 1)
    current_usage_log.increment!(:child_created_count, count)
  end

  def current_usage_log
    client_usage_logs.find_or_create_by!(period: usage_period_key)
  end

  def title_suggestion_usage_count
    current_usage_log.title_suggestion_count
  end

  def image_generation_usage_count
    reconcile_image_generation_usage_if_drifted!
    current_usage_log.image_generation_count
  end

  def actual_image_generation_count
    columns.where.not(file: [nil, ""]).count
  end

  def reconcile_image_generation_usage_if_drifted!
    actual = actual_image_generation_count
    log = current_usage_log
    return if log.image_generation_count <= actual

    Rails.logger.warn(
      "[Client #{id}] image_generation_count drift detected: " \
      "logged=#{log.image_generation_count}, actual=#{actual}. correcting."
    )
    log.update_column(:image_generation_count, actual)
  end

  def can_use_api?
    plan_limits[:api_enabled]
  end

  def regenerate_api_key!
    update!(api_key: SecureRandom.hex(32))
  end

  def can_create_pillar?(count: 1, excluding: nil)
    pillar_slots_used(excluding: excluding) + count <= plan_limits[:pillar_articles]
  end

  def can_create_child?(count: 1, excluding: nil)
    child_slots_used(excluding: excluding) + count <= plan_limits[:child_articles]
  end

  def can_suggest_titles?
    title_suggestion_usage_count < plan_limits[:title_suggestions]
  end

  def max_title_suggestion_count
    (plan_limits[:title_suggestion_max_per_use] || Subscription::TITLE_SUGGESTION_BAR_MAX)
      .to_i
      .clamp(1, Subscription::TITLE_SUGGESTION_BAR_MAX)
  end

  def can_generate_images?(count: 1)
    image_generation_usage_count + count <= plan_limits[:image_generations]
  end

  def can_add_genre?
    service_genres.count < plan_limits[:genre_count]
  end

  def can_suggest_genre?
    genre_suggestion_usage_count < plan_limits.fetch(:genre_suggestions, 999)
  end

  def genre_suggestion_usage_count
    current_usage_log.genre_suggestion_count
  end

  def record_genre_suggestion!
    current_usage_log.increment!(:genre_suggestion_count)
  end

  def max_sub_category_count
    plan_limits[:sub_category_count].to_i
  end

  def sub_categories_allowed?
    max_sub_category_count.positive?
  end

  def ai_autonomous_enabled?
    plan_limits[:ai_autonomous]
  end

  # Standard 以下は true。Business / Enterprise、および自社ジャンルは false。
  def attribution_required?(genre: nil, column: nil)
    AttributionPolicy.required?(client: self, genre: genre, column: column)
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
    reconcile_image_generation_usage_if_drifted!
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
    when :genre_suggestion
      "ジャンルAI提案の上限（#{limits.fetch(:genre_suggestions, 1)}回）に達しています。プランのアップグレードをご検討ください。"
    when :sub_category
      if limits[:sub_category_count].to_i <= 0
        "お使いのプランでは中分類を利用できません。スタンダードプラン以上でご利用いただけます。"
      else
        "中分類の上限（#{limits[:sub_category_count]}件）に達しています。プランのアップグレードをご検討ください。"
      end
    when :api
      "現在のプランではAPIを利用できません。プランのアップグレードをご検討ください。"
    when :ai_autonomous
      "AI主導生成はビジネスプラン以上で利用できます。"
    else
      "プランの利用上限に達しています。"
    end
  end

  def usage_summary
    return @usage_summary if defined?(@usage_summary)

    @usage_summary = Rails.cache.fetch("client:#{id}:usage_summary:#{usage_period_key}", expires_in: 60.seconds) do
      build_usage_summary
    end
  end

  def build_usage_summary
    limits = plan_limits
    log = current_usage_log
    pillar_used = log.pillar_created_count
    child_used = log.child_created_count

    {
      pillar: { used: pillar_used, limit: limits[:pillar_articles] },
      child: { used: child_used, limit: limits[:child_articles] },
      title_suggestions: { used: current_usage_log.title_suggestion_count, limit: limits[:title_suggestions] },
      # サイドバー表示では全件 file COUNT の reconcile を避ける（書き込み時に加算済み）
      image_generations: { used: current_usage_log.image_generation_count, limit: limits[:image_generations] },
      genres: { used: service_genres.count, limit: limits[:genre_count] },
      genre_suggestions: { used: current_usage_log.genre_suggestion_count, limit: limits.fetch(:genre_suggestions, 999) },
      sub_categories: { limit: limits[:sub_category_count] },
      api_enabled: limits[:api_enabled],
      ai_autonomous: limits[:ai_autonomous],
      attribution_required: limits.fetch(:attribution_required, true)
    }
  end

  def approaching_limit?(threshold: 0.8)
    usage_summary.any? do |_key, row|
      next false unless row.is_a?(Hash) && row[:limit].present? && row[:limit].to_i.positive? && row.key?(:used)

      row[:used].to_f / row[:limit] >= threshold
    end
  end

  def trial_expired_without_paid?
    subscription = current_subscription
    return true if subscription&.expired?
    return true if subscription_plan == "trial" && trial_ends_at.present? && trial_ends_at <= Time.current

    false
  end

  # トライアル終了時は自動課金せず期限切れにする（有料プランは手動誘導）
  def check_and_upgrade_expired_trial
    return unless subscription_plan == "trial"
    return unless trial_ends_at.present?
    return if trial_ends_at > Time.current

    current_subscription&.expire_trial_without_charge!
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

  def initialize_trial_subscription!
    return current_subscription if subscriptions.where(plan_type: :trial).exists?

    ends_at = Subscription::TRIAL_DAYS.days.from_now
    subscription = subscriptions.create!(
      plan_type: :trial,
      status: :active,
      trial_ends_at: ends_at
    )
    update_columns(
      subscription_plan: "trial",
      subscription_status: "active",
      trial_ends_at: ends_at
    )
    subscription
  end

  after_create :bootstrap_trial_subscription
  before_create :generate_api_key_if_blank

  private

  def generate_api_key_if_blank
    self.api_key = SecureRandom.hex(32) if api_key.blank?
  end

  def bootstrap_trial_subscription
    initialize_trial_subscription!
  end

end