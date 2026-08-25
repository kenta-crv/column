# frozen_string_literal: true

# 公開コラム記事下部（関連記事の直前）に出す自社サービスCTA。
# 優先順位: ServiceGenre.column_cta（ダッシュボード編集） → コード上のデフォルト CTAS
class ColumnServiceCta
  CTAS = {
    ai_sales_agent: {
      enabled: true,
      theme: "meetia",
      badge: "Meetia",
      title: "資料をアップロードするだけ。AIが24時間商談代行",
      lead: "営業担当の代わりにAIアバター「ミーティア」が即時商談。見込み度分析から自動追客まで一気通貫です。",
      cta_label: "無料で商談体験",
      path: "/",
      en: {
        title: "Upload your deck. AI runs meetings 24/7",
        lead: "Meetia, an AI avatar, takes meetings for your sales team—from lead scoring to automated follow-up.",
        cta_label: "Try a meeting free"
      }
    },
    app: {
      enabled: true,
      theme: "okurite",
      badge: "Okurite",
      title: "AI×プロで、営業成果を仕組み化する",
      lead: "フォーム営業・テレアポ・インサイドセールスまで。低コストで大量アプローチできる営業代行です。",
      cta_label: "Okuriteのサービスを見る",
      path: "/okurite",
      en: {
        title: "Turn sales results into a system with AI + pros",
        lead: "From form outreach and cold calls to inside sales. High-volume outreach at a lower cost.",
        cta_label: "See Okurite"
      }
    },
    cargo: {
      enabled: true,
      theme: "jwork",
      badge: "J Work",
      title: "外国人材の採用・紹介はLINEで相談",
      lead: "条件に合う登録者数を先にお伝えします。まずはお気軽にご相談ください。",
      cta_label: "採用の相談（LINE）",
      url: "https://lin.ee/NZBWRrsD",
      en: {
        title: "Hire foreign talent—chat on LINE",
        lead: "We’ll show how many registered candidates match your conditions first.",
        cta_label: "Talk hiring (LINE)"
      },
      by_sub_genre: {
        delivery_partner: {
          theme: "jwork",
          badge: "J Work",
          title: "Amazon配送の外国人材確保・業務請負はLINEで",
          lead: "外国人ドライバーの採用や業務請負について、まずはご相談ください。",
          cta_label: "新規取引相談（LINE）",
          url: "https://lin.ee/NZBWRrsD",
          en: {
            title: "Amazon delivery staffing with foreign drivers—chat on LINE",
            lead: "Talk to us about hiring foreign drivers or contracted delivery operations.",
            cta_label: "New partnership (LINE)"
          }
        },
        foreign_hiring: {
          theme: "jwork",
          badge: "企業向け",
          title: "外国人雇用・求人掲載はLINEで",
          lead: "助成金や受け入れの相談、求人の無料掲載もご案内します。",
          cta_label: "雇用の相談（LINE）",
          url: "https://lin.ee/NZBWRrsD",
          en: {
            badge: "For employers",
            title: "Hiring foreign talent and job posts—on LINE",
            lead: "Ask about subsidies, onboarding, or posting a job for free.",
            cta_label: "Talk hiring (LINE)"
          }
        },
        driver_recruitment: {
          theme: "jwork-recruit",
          badge: "求職者向け",
          title: "日本でのお仕事探しはLINEで",
          lead: "配送を含む求人情報をLINEで受け取れます。未経験の方も歓迎です。",
          cta_label: "お仕事の応募（LINE）",
          url: "https://lin.ee/8pGADE1",
          en: {
            badge: "For job seekers",
            title: "Find work in Japan on LINE",
            lead: "Job updates including delivery roles. No experience required.",
            cta_label: "Apply via LINE"
          }
        },
        life_guide: {
          theme: "jwork-recruit",
          badge: "生活サポート",
          title: "仕事と暮らしの相談はLINEで",
          lead: "手続きで困ったときも、求人情報もLINEで案内します。",
          cta_label: "相談する（LINE）",
          url: "https://lin.ee/8pGADE1",
          en: {
            badge: "Life in Japan",
            title: "Work and daily life—ask on LINE",
            lead: "Get help with paperwork and job updates.",
            cta_label: "Chat on LINE"
          }
        },
        specified_skills: {
          theme: "jwork",
          badge: "企業向け",
          title: "特定技能・技能実習の受け入れ相談はLINEで",
          lead: "制度の整理と、現場で動ける人材のご案内をします。",
          cta_label: "受け入れの相談（LINE）",
          url: "https://lin.ee/NZBWRrsD",
          en: {
            badge: "For employers",
            title: "Specified skilled & intern programs—chat on LINE",
            lead: "We’ll help you sort the system and find people who can start.",
            cta_label: "Talk hiring (LINE)"
          }
        },
        support_orgs: {
          theme: "jwork",
          badge: "支援団体向け",
          title: "団体掲載・連携のご相談はLINEで",
          lead: "支援団体の紹介、イベント告知、企業・求職者との橋渡しをご相談ください。",
          cta_label: "連携の相談（LINE）",
          url: "https://lin.ee/NZBWRrsD",
          en: {
            badge: "For organizations",
            title: "List your organization or partner with us on LINE",
            lead: "Profiles, events, and introductions to employers and job seekers.",
            cta_label: "Talk partnership (LINE)"
          }
        },
        labor_help: {
          theme: "jwork-recruit",
          badge: "相談窓口",
          title: "困ったときはまず相談を。LINEでも案内します",
          lead: "未払い・ハラスメントなどは公的窓口が本筋です。行き先が分からない場合はLINEで案内します。",
          cta_label: "窓口を聞く（LINE）",
          url: "https://lin.ee/8pGADE1",
          en: {
            badge: "Get help",
            title: "If you’re in trouble, start here—or ask on LINE",
            lead: "Wage theft and harassment belong at official desks. We’ll help you find the right one.",
            cta_label: "Ask where to go (LINE)"
          }
        }
      }
    },
    vender: {
      enabled: true,
      theme: "vender",
      badge: "自販機ねっと",
      title: "自動販売機の設置・購入を無料相談",
      lead: "無料設置から本体購入まで。立地や運営方針に合わせた最適なプランをご提案します。",
      cta_label: "設置・購入について相談する",
      path: "/",
      en: {
        title: "Free consult for vending machine placement or purchase",
        lead: "From free placement to buying your own machine. We propose a plan that fits the site and how you want to operate.",
        cta_label: "Talk about placement or purchase"
      }
    },
    cleaning: {
      enabled: true,
      theme: "okwork",
      badge: "OK清掃",
      title: "日常清掃・施設清掃はOK清掃へ",
      lead: "20〜50代中心のスタッフ体制で、施設の美観と衛生を安定運用します。",
      cta_label: "清掃サービスを見る",
      path: "/",
      en: {
        title: "Daily and facility cleaning with OK Cleaning",
        lead: "Staffed mainly by people in their 20s–50s, we keep facilities looking and feeling clean.",
        cta_label: "See cleaning services"
      },
      by_sub_genre: {
        special: {
          badge: "OK特殊クリーン",
          title: "特殊清掃・緊急対応のご相談",
          lead: "専門機材とプロの技術で、迅速かつ丁寧に対応します。",
          cta_label: "特殊清掃について相談する",
          path: "/",
          en: {
            title: "Specialized and emergency cleaning",
            lead: "Professional equipment and technique for a fast, careful response.",
            cta_label: "Talk about specialized cleaning"
          }
        }
      }
    },
    housekeeping: {
      enabled: true,
      theme: "kurasera",
      badge: "クラセラ",
      title: "家事代行はクラセラ",
      lead: "掃除・洗濯・片付けなど、暮らしの家事負担をプロがサポートします。",
      cta_label: "クラセラのサービスを見る",
      path: "/",
      en: {
        title: "Housekeeping with Kurasera",
        lead: "Pros handle cleaning, laundry, and tidying so everyday chores take less of your time.",
        cta_label: "See Kurasera"
      }
    },
    ai_interview: {
      enabled: true,
      theme: "recrivo",
      badge: "Recrivo",
      title: "一次面接をAIが代行。採用スピードを上げる",
      lead: "求職者が好きな時間にAI面接を受診。評価結果を可視化し、面接工数を削減します。",
      cta_label: "Recrivoを見る",
      path: "/",
      en: {
        title: "AI runs first-round interviews so hiring moves faster",
        lead: "Candidates take an AI interview on their own schedule. Scores are visible, and interview hours drop.",
        cta_label: "See Recrivo"
      }
    },
    ai_article_generation: {
      enabled: true,
      theme: "drafity",
      badge: "Drafity",
      title: "SEO記事を、ピラー／クラスターで自動生成",
      lead: "検索需要に沿った高品質記事を短時間で生成。オウンドメディアの資産化を加速します。",
      cta_label: "Drafityを始める",
      path: "/",
      en: {
        title: "Generate SEO articles with a pillar / cluster structure",
        lead: "High-quality articles aligned with search demand, in less time. Grow owned media as an asset.",
        cta_label: "Start Drafity"
      }
    },
    ai_article: {
      enabled: true,
      theme: "drafity",
      badge: "Drafity",
      title: "AI記事生成でコンテンツSEOを加速",
      lead: "親記事・子記事の設計から生成まで。検索流入につながる記事運用を支援します。",
      cta_label: "サービスを見る",
      path: "/",
      en: {
        title: "Speed up content SEO with AI article generation",
        lead: "From pillar and cluster design through generation. We help you run articles that earn search traffic.",
        cta_label: "See the service"
      }
    }
  }.freeze

  THEME_OPTION_VALUES = %w[
    meetia
    okurite
    jwork
    jwork-recruit
    vender
    okwork
    kurasera
    recrivo
    drafity
    default
  ].freeze

  def self.theme_options
    THEME_OPTION_VALUES.map do |value|
      [I18n.t("drafity.dashboard.genres.theme_options.#{value.tr('-', '_')}"), value]
    end
  end

  def self.resolve(column)
    return nil if column.blank?

    key = GenreRegistry.canonical_key(column.genre)&.to_sym
    return nil if key.blank?

    base = stored_payload_for(column, key) || default_payload_for(key)
    return nil if base.blank?
    return nil if disabled?(base)

    sub_key = GenreRegistry.resolve_sub_category_key(column, key)
    override = dig_sub_genre(base, sub_key)
    apply_locale_copy(merge_cta(base, override), column, key, sub_key, base, override)
  end

  def self.default_payload_for(key)
    canon = GenreRegistry.canonical_key(key)&.to_sym
    return nil if canon.blank?

    CTAS[canon]&.deep_dup
  end

  def self.stringify_payload(payload)
    case payload
    when Hash
      payload.each_with_object({}) do |(k, v), result|
        result[k.to_s] = stringify_payload(v)
      end
    when Array
      payload.map { |item| stringify_payload(item) }
    else
      payload
    end
  end

  def self.symbolize_payload(payload)
    case payload
    when Hash
      payload.each_with_object({}) do |(k, v), result|
        result[k.to_sym] = symbolize_payload(v)
      end
    when Array
      payload.map { |item| symbolize_payload(item) }
    else
      payload
    end
  end

  def self.stored_payload_for(column, key)
    return nil unless ServiceGenre.table_exists?
    return nil unless ServiceGenre.column_names.include?("column_cta")

    keys = GenreRegistry.equivalent_keys(key)
    scope = ServiceGenre.where(key: keys)

    record = scope.find_by(client_id: column.client_id) if column.client_id.present?
    record ||= scope.find_by(client_id: nil)
    return nil if record.blank?

    raw = record.column_cta
    return nil if blank_payload?(raw)

    symbolize_payload(raw)
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    nil
  end

  def self.blank_payload?(payload)
    return true if payload.blank?

    data = payload.with_indifferent_access
    data[:title].blank? && data[:cta_label].blank? && data[:url].blank? && data[:path].blank? && data[:badge].blank?
  end

  def self.disabled?(payload)
    flag = payload.with_indifferent_access[:enabled]
    flag == false || flag.to_s == "false" || flag.to_s == "0"
  end

  def self.dig_sub_genre(base, sub_key)
    return nil if sub_key.blank?

    by_sub = base.with_indifferent_access[:by_sub_genre]
    return nil unless by_sub.is_a?(Hash)

    by_sub[sub_key.to_s].presence || by_sub[sub_key.to_sym].presence
  end

  COPY_KEYS = %i[title lead cta_label badge].freeze

  def self.merge_cta(base, override)
    data = base.except(:by_sub_genre, "by_sub_genre")
    data = symbolize_payload(data)
    return data if override.blank?

    data.merge(symbolize_payload(override).except(:by_sub_genre))
  end

  def self.apply_locale_copy(payload, column, key, sub_key, base, override)
    return payload unless Column.english_language?(column&.language)

    default = default_payload_for(key)
    en_copy = extract_en_copy(default)
    en_copy = en_copy.merge(extract_en_copy(base))
    if sub_key.present?
      en_copy = en_copy.merge(extract_en_copy(dig_sub_genre(default, sub_key)))
      en_copy = en_copy.merge(extract_en_copy(override))
    end

    data = symbolize_payload(payload.except(:en, "en", :by_sub_genre, "by_sub_genre"))
    COPY_KEYS.each do |copy_key|
      data[copy_key] = en_copy[copy_key] if en_copy[copy_key].present?
    end
    data
  end

  def self.extract_en_copy(payload)
    return {} if payload.blank?

    en = payload.with_indifferent_access[:en]
    return {} unless en.is_a?(Hash)

    symbolize_payload(en).slice(*COPY_KEYS).compact
  end
  private_class_method :merge_cta, :dig_sub_genre, :disabled?, :blank_payload?,
                       :apply_locale_copy, :extract_en_copy
end
