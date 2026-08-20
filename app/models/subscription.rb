class Subscription < ApplicationRecord
  belongs_to :client

  enum plan_type: {
    trial: "trial",
    starter: "starter",
    standard: "standard",
    business: "business",
    enterprise: "enterprise"
  }

  enum status: { active: "active", cancelled: "cancelled", expired: "expired" }

  validates :plan_type, presence: true
  validates :status, presence: true
  validates :stripe_subscription_id, uniqueness: true, allow_nil: true

  after_commit :notify_registered, on: :create
  after_commit :notify_updated, on: :update

  TRIAL_DAYS = 14
  # 年額割引は当面使わない（表示・Checkout から除外）
  YEARLY_DISCOUNT_RATE = 0.8
  POST_TRIAL_PLAN = :standard
  STANDARD_INTRO_PERCENT_OFF = 15
  STANDARD_INTRO_MONTHS = 3
  TITLE_SUGGESTION_BAR_MAX = 5
  TITLE_SUGGESTION_ADMIN_BAR_MAX = 50

  # プラン定義の唯一のソース（LP・管理画面・決済・上限チェックで共通利用）
  # price: JPY表示額 / prices: 通貨別表示額（usdはドル単位）
  PLANS = {
    trial: {
      name: "トライアル",
      name_en: "Trial",
      lp_name: "トライアル",
      description: "#{TRIAL_DAYS}日間。カード不要。終了後はスタンダードへ誘導",
      description_en: "#{TRIAL_DAYS} days, no card. Then guided to Standard",
      price: 0,
      prices: { jpy: 0, usd: 0 },
      pillar_articles: 1,
      child_articles: 5,
      title_suggestions: 3,
      title_suggestion_max_per_use: 1,
      image_generations: 8,
      genre_suggestions: 1,
      genre_count: 1,
      sub_category_count: 0,
      api_enabled: false,
      ai_autonomous: false,
      attribution_required: true,
      lp_popular: false,
      lp_featured: false,
      lp_cta: "無料で始める →",
      lp_note: "",
      show_on_lp: true,
      checkout_selectable: false,
      purchasable: false,
      post_trial_plan: :standard,
      stripe_price_env: nil
    },
    starter: {
      name: "スターター",
      name_en: "Starter",
      lp_name: "スターター",
      description: "（新規販売停止）",
      description_en: "(Not available for new purchases)",
      price: 29_800,
      prices: { jpy: 29_800, usd: 199 },
      pillar_articles: 3,
      child_articles: 45,
      title_suggestions: 3,
      title_suggestion_max_per_use: 3,
      image_generations: 60,
      genre_suggestions: 999,
      genre_count: 1,
      sub_category_count: 0,
      api_enabled: true,
      ai_autonomous: false,
      attribution_required: true,
      lp_popular: false,
      lp_featured: false,
      lp_cta: "このプランで始める →",
      lp_note: "",
      show_on_lp: false,
      checkout_selectable: false,
      purchasable: false,
      stripe_price_env: "STRIPE_PRICE_STARTER",
      stripe_price_envs: {
        jpy: "STRIPE_PRICE_STARTER",
        usd: "STRIPE_PRICE_STARTER_USD",
      }
    },
    standard: {
      name: "スタンダード",
      name_en: "Standard",
      lp_name: "スタンダード",
      description: "本格的にメディア運用を始めたい方へ",
      description_en: "For teams starting serious media operations",
      price: 49_800,
      prices: { jpy: 49_800, usd: 349 },
      pillar_articles: 5,
      child_articles: 75,
      title_suggestions: 5,
      title_suggestion_max_per_use: 5,
      image_generations: 125,
      genre_suggestions: 999,
      genre_count: 3,
      sub_category_count: 3,
      api_enabled: true,
      ai_autonomous: false,
      attribution_required: true,
      lp_popular: true,
      lp_featured: false,
      lp_cta: "このプランで始める →",
      lp_note: "",
      show_on_lp: true,
      checkout_selectable: true,
      purchasable: true,
      stripe_price_env: "STRIPE_PRICE_STANDARD",
      stripe_price_envs: {
        jpy: "STRIPE_PRICE_STANDARD",
        usd: "STRIPE_PRICE_STANDARD_USD",
      },
      intro_coupon_env: "STRIPE_COUPON_STANDARD_INTRO"
    },
    business: {
      name: "ビジネス",
      name_en: "Business",
      lp_name: "ビジネス",
      description: "複数メディアの運営やチーム利用に最適",
      description_en: "For multi-site ops and team use",
      price: 98_000,
      prices: { jpy: 98_000, usd: 699 },
      pillar_articles: 15,
      child_articles: 225,
      title_suggestions: 30,
      title_suggestion_max_per_use: 5,
      image_generations: 250,
      genre_suggestions: 999,
      genre_count: 10,
      sub_category_count: 10,
      api_enabled: true,
      ai_autonomous: true,
      attribution_required: false,
      lp_popular: false,
      lp_featured: true,
      lp_cta: "このプランで始める →",
      lp_note: "",
      show_on_lp: true,
      checkout_selectable: true,
      purchasable: true,
      stripe_price_env: "STRIPE_PRICE_BUSINESS",
      stripe_price_envs: {
        jpy: "STRIPE_PRICE_BUSINESS",
        usd: "STRIPE_PRICE_BUSINESS_USD",
      }
    },
    enterprise: {
      name: "エンタープライズ",
      name_en: "Enterprise",
      lp_name: "エンタープライズ",
      description: "大規模運用・カスタマイズが必要な企業様へ",
      description_en: "For large-scale ops and customization",
      price: 198_000,
      prices: { jpy: 198_000, usd: 1_299 },
      pillar_articles: 50,
      child_articles: 750,
      title_suggestions: 100,
      title_suggestion_max_per_use: 5,
      image_generations: 1000,
      genre_suggestions: 999,
      genre_count: 20,
      sub_category_count: 10,
      api_enabled: true,
      ai_autonomous: true,
      attribution_required: false,
      lp_popular: false,
      lp_featured: false,
      lp_cta: "問い合わせる →",
      lp_note: "",
      show_on_lp: true,
      checkout_selectable: true,
      purchasable: true,
      stripe_price_env: "STRIPE_PRICE_ENTERPRISE",
      stripe_price_envs: {
        jpy: "STRIPE_PRICE_ENTERPRISE",
        usd: "STRIPE_PRICE_ENTERPRISE_USD",
      }
    }
  }.freeze

  PLAN_ORDER = PLANS.keys.freeze
  PAID_PLAN_TYPES = (PLAN_ORDER - [:trial]).freeze

  # 後方互換（既存コード向け）
  PLAN_NAMES = PLANS.transform_values { |v| "#{v[:name]}プラン" }.freeze
  PLAN_PRICES = PLANS.transform_values { |v| v[:price] }.freeze

  class << self
    def config_for(plan_key)
      key = plan_key.to_s.presence&.to_sym
      PLANS[key] || PLANS[:trial] || {}
    end

    def plan_config(plan_type)
      return nil if plan_type.blank?

      PLANS[plan_type.to_sym]
    end

    def public_plans
      PLANS.select { |_key, config| config[:show_on_lp] }
    end

    def purchasable_plans
      PLANS.select { |_key, config| config[:purchasable] }
    end

    def price_for(plan_type, currency: :jpy)
      config = plan_config(plan_type) || config_for(plan_type)
      return 0 if config.blank?

      currency = currency.to_sym
      config.dig(:prices, currency) || (currency == :jpy ? config[:price] : nil) || config[:price] || 0
    end

    def intro_price_for(plan_type, currency: :jpy)
      base = price_for(plan_type, currency: currency).to_f
      (base * (100 - STANDARD_INTRO_PERCENT_OFF) / 100.0).round
    end

    def format_price(plan_type, currency: :jpy)
      amount = price_for(plan_type, currency: currency)
      return BillingCurrency.symbol(currency) + "0" if amount.to_i.zero?

      case currency.to_sym
      when :usd
        "#{BillingCurrency.symbol(currency)}#{amount}"
      else
        "¥#{amount.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
      end
    end

    def lp_plans(currency: :jpy)
      currency = currency.to_sym
      PLAN_ORDER.filter_map do |key|
        config = PLANS[key]
        next unless config[:show_on_lp]

        i18n_key = "drafity.plans.#{key}"
        monthly = price_for(key, currency: currency)
        {
          key: key,
          name: I18n.t("#{i18n_key}.name", default: config[:lp_name]),
          description: I18n.t("#{i18n_key}.description", default: config[:description]),
          monthly_price: monthly,
          formatted_price: format_price(key, currency: currency),
          currency: currency,
          currency_symbol: BillingCurrency.symbol(currency),
          note: I18n.t("#{i18n_key}.note", default: config[:lp_note]),
          cta_text: I18n.t("#{i18n_key}.cta", default: config[:lp_cta]),
          popular: config[:lp_popular],
          featured: config[:lp_featured],
          features: feature_list_for(key)
        }
      end
    end

    def checkout_plans
      PAID_PLAN_TYPES.select { |key| PLANS[key][:checkout_selectable] }
    end

    def feature_list_for(plan_key)
      config = config_for(plan_key)
      return [] if config.blank?

      period = if plan_key.to_sym == :trial
                 I18n.t("drafity.plans.features.period_trial", default: "期間中")
               else
                 I18n.t("drafity.plans.features.period_month", default: "月")
               end

      features = [
        I18n.t("drafity.plans.features.pillar", count: config[:pillar_articles], period: period, default: "親記事 #{period}#{config[:pillar_articles]}記事"),
        I18n.t("drafity.plans.features.child", count: config[:child_articles], period: period, default: "子記事 #{period}#{config[:child_articles]}記事"),
        I18n.t("drafity.plans.features.titles", count: config[:title_suggestions], default: "AIタイトル提案 #{config[:title_suggestions]}回"),
        I18n.t("drafity.plans.features.images", count: config[:image_generations], default: "画像生成 #{config[:image_generations]}回"),
        I18n.t("drafity.plans.features.genres", count: config[:genre_count], default: "ジャンル #{config[:genre_count]}個まで")
      ]

      features << sub_category_feature_for(plan_key)
      features << if config[:api_enabled]
                    I18n.t("drafity.plans.features.api_on", default: "API利用可")
                  else
                    I18n.t("drafity.plans.features.api_off", default: "API利用不可")
                  end
      features << if config[:ai_autonomous]
                    I18n.t("drafity.plans.features.autonomous", default: "AI主導生成（自律型エージェント）")
                  else
                    I18n.t("drafity.plans.features.autonomous_off", default: "AI主導生成なし")
                  end
      features << if config[:attribution_required]
                    I18n.t("drafity.plans.features.attribution_on", default: "Powered by 表示あり")
                  else
                    I18n.t("drafity.plans.features.attribution_off", default: "Powered by 表示なし")
                  end
      features
    end

    def yearly_price_for(monthly_price)
      return 0 if monthly_price.to_i <= 0

      (monthly_price * YEARLY_DISCOUNT_RATE).to_i
    end

    def stripe_price_env_key(plan_key, currency: :jpy)
      config = plan_config(plan_key)
      return "STRIPE_PRICE_#{plan_key.to_s.upcase}" if config.blank?

      config.dig(:stripe_price_envs, currency.to_sym) || config[:stripe_price_env] || "STRIPE_PRICE_#{plan_key.to_s.upcase}"
    end

    def stripe_price_id_for(plan_key, currency: :jpy)
      env_key = stripe_price_env_key(plan_key, currency: currency)
      return nil if env_key.blank?

      ENV[env_key].presence
    end

    def intro_coupon_id_for(plan_type)
      env_key = plan_config(plan_type)&.dig(:intro_coupon_env)
      return nil if env_key.blank?

      ENV[env_key].presence
    end

    def sub_category_feature_for(plan_key)
      count = config_for(plan_key)[:sub_category_count].to_i
      if count <= 0
        I18n.t("drafity.plans.features.sub_none", default: "中分類なし")
      else
        I18n.t("drafity.plans.features.sub_count", count: count, default: "中分類 #{count}件まで")
      end
    end

    def limits_for(plan_key)
      config = config_for(plan_key)
      config.slice(
        :pillar_articles,
        :child_articles,
        :title_suggestions,
        :title_suggestion_max_per_use,
        :image_generations,
        :genre_count,
        :sub_category_count,
        :api_enabled,
        :ai_autonomous,
        :attribution_required
      )
    end
  end

  def plan_config
    self.class.config_for(plan_type)
  end

  def limits
    self.class.limits_for(plan_type)
  end

  def plan_key
    self[:plan_type].to_s.presence&.to_sym
  end

  def known_plan_key?
    plan_key.present? && PLANS.key?(plan_key)
  end

  def plan_name
    raw_plan_type = self[:plan_type].to_s
    return raw_plan_type if raw_plan_type.present? && !known_plan_key?

    PLAN_NAMES[plan_key] || "不明"
  end

  def display_name
    return plan_name unless known_plan_key?

    plan_config[:lp_name].presence || plan_name
  end

  def self.display_name_for(plan_key)
    normalized_key = plan_key.to_s.presence&.to_sym
    config_for(normalized_key)[:lp_name].presence || PLAN_NAMES[normalized_key] || plan_key.to_s.presence || "不明"
  end

  def price
    return 0 unless known_plan_key?

    plan_config[:price] || 0
  end

  def yearly_price
    self.class.yearly_price_for(price)
  end

  def feature_list
    return [] unless known_plan_key?

    self.class.feature_list_for(plan_type)
  end

  # 後方互換: 記事生成上限の合計
  def delivery_limit
    (limits[:pillar_articles] || 0) + (limits[:child_articles] || 0)
  end

  def api_enabled?
    limits[:api_enabled]
  end

  def ai_autonomous?
    limits[:ai_autonomous]
  end

  def unlimited?
    false
  end

  def trial?
    plan_key == :trial
  end

  def paid?
    !trial?
  end

  def trial_active?
    trial? && trial_ends_at.present? && trial_ends_at > Time.current
  end

  def trial_expired?
    trial? && trial_ends_at.present? && trial_ends_at <= Time.current
  end

  # 自動課金せず期限切れにする（閲覧継続・有料は手動でスタンダード等へ）
  def expire_trial_without_charge!
    return unless trial?
    return if trial_ends_at.blank?
    return if trial_ends_at > Time.current
    return if status != "active"

    update!(status: :expired)
    client.update_columns(
      subscription_status: "expired",
      trial_ends_at: trial_ends_at
    ) if client.has_attribute?(:subscription_status)
  end

  def expire_trial_and_upgrade!
    expire_trial_without_charge!
  end

  private

  def notify_registered
    SubscriptionNotifier.registered(self)
  end

  def notify_updated
    if saved_change_to_status? && cancelled?
      SubscriptionNotifier.cancelled(self)
    elsif saved_change_to_plan_type?
      SubscriptionNotifier.changed(self, previous_plan: plan_type_before_last_save)
    end
  end
end
