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

  TRIAL_DAYS = 14
  YEARLY_DISCOUNT_RATE = 0.8
  POST_TRIAL_PLAN = :standard
  TITLE_SUGGESTION_BAR_MAX = 5
  TITLE_SUGGESTION_ADMIN_BAR_MAX = 50

  # プラン定義の唯一のソース（LP・管理画面・決済・上限チェックで共通利用）
  PLANS = {
    trial: {
      name: "トライアル",
      lp_name: "トライアル",
      description: "まずはAI記事作成を気軽に試したい方へ",
      price: 0,
      pillar_articles: 1,
      child_articles: 3,
      title_suggestions: 1,
      title_suggestion_max_per_use: 1,
      image_generations: 5,
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
      checkout_selectable: true
    },
    starter: {
      name: "スターター",
      lp_name: "スターター",
      description: "個人ブロガーや小規模サイトの運営におすすめ",
      price: 29_800,
      pillar_articles: 3,
      child_articles: 45,
      title_suggestions: 3,
      title_suggestion_max_per_use: 3,
      image_generations: 60,
      genre_count: 1,
      sub_category_count: 0,
      api_enabled: true,
      ai_autonomous: false,
      attribution_required: true,
      lp_popular: false,
      lp_featured: false,
      lp_cta: "このプランで始める →",
      lp_note: "年額払いで20%お得",
      show_on_lp: true,
      checkout_selectable: true
    },
    standard: {
      name: "スタンダード",
      lp_name: "スタンダード",
      description: "本格的にメディア運用を始めたい方へ",
      price: 49_800,
      pillar_articles: 5,
      child_articles: 75,
      title_suggestions: 5,
      title_suggestion_max_per_use: 5,
      image_generations: 125,
      genre_count: 3,
      sub_category_count: 3,
      api_enabled: true,
      ai_autonomous: false,
      attribution_required: true,
      lp_popular: true,
      lp_featured: false,
      lp_cta: "このプランで始める →",
      lp_note: "年額払いで20%お得",
      show_on_lp: true,
      checkout_selectable: true
    },
    business: {
      name: "ビジネス",
      lp_name: "ビジネス",
      description: "複数メディアの運営やチーム利用に最適",
      price: 98_000,
      pillar_articles: 15,
      child_articles: 225,
      title_suggestions: 30,
      title_suggestion_max_per_use: 5,
      image_generations: 250,
      genre_count: 10,
      sub_category_count: 10,
      api_enabled: true,
      ai_autonomous: true,
      attribution_required: false,
      lp_popular: false,
      lp_featured: true,
      lp_cta: "このプランで始める →",
      lp_note: "年額払いで20%お得",
      show_on_lp: true,
      checkout_selectable: true
    },
    enterprise: {
      name: "エンタープライズ",
      lp_name: "エンタープライズ",
      description: "大規模運用・カスタマイズが必要な企業様へ",
      price: 198_000,
      pillar_articles: 50,
      child_articles: 750,
      title_suggestions: 100,
      title_suggestion_max_per_use: 5,
      image_generations: 1000,
      genre_count: 20,
      sub_category_count: 10,
      api_enabled: true,
      ai_autonomous: true,
      attribution_required: false,
      lp_popular: false,
      lp_featured: false,
      lp_cta: "問い合わせる →",
      lp_note: "年額払いで20%お得",
      show_on_lp: true,
      checkout_selectable: true
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

    def lp_plans
      PLAN_ORDER.filter_map do |key|
        config = PLANS[key]
        next unless config[:show_on_lp]

        i18n_key = "drafity.plans.#{key}"
        {
          key: key,
          name: I18n.t("#{i18n_key}.name", default: config[:lp_name]),
          description: I18n.t("#{i18n_key}.description", default: config[:description]),
          monthly_price: config[:price],
          yearly_price: yearly_price_for(config[:price]),
          note: I18n.t("#{i18n_key}.note", default: config[:lp_note]),
          cta_text: I18n.t("#{i18n_key}.cta", default: config[:lp_cta]),
          popular: config[:lp_popular],
          featured: config[:lp_featured],
          features: feature_list_for(key)
        }
      end
    end

    def checkout_plans
      PAID_PLAN_TYPES
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
      features << I18n.t("drafity.plans.features.autonomous", default: "AI主導生成（自律型エージェント）") if config[:ai_autonomous]
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

    def stripe_price_env_key(plan_key)
      "STRIPE_PRICE_#{plan_key.to_s.upcase}"
    end

    def stripe_price_id_for(plan_key)
      ENV[stripe_price_env_key(plan_key)]
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

  def expire_trial_and_upgrade!
    return unless trial?
    return if trial_ends_at.blank?
    return if trial_ends_at > Time.current
    return if status != "active"

    upgrade_plan = POST_TRIAL_PLAN

    transaction do
      update!(status: :expired)

      client.subscriptions.where(status: :active).update_all(status: :cancelled)

      client.subscriptions.create!(
        plan_type: upgrade_plan,
        status: :active
      )

      client.update!(
        subscription_plan: upgrade_plan.to_s,
        subscription_status: "active",
        trial_ends_at: nil
      )
    end
  end
end
