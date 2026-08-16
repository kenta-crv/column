module ApplicationHelper
  ADMIN_PAGE_TITLE_KEYS = {
    ["dashboard/columns", "index"] => "drafity.dashboard.page_titles.articles",
    ["dashboard/columns", "image_generation"] => "drafity.dashboard.page_titles.image_generation",
    ["dashboard/columns", "management"] => "drafity.dashboard.page_titles.management",
    ["dashboard/columns", "setting"] => "drafity.dashboard.page_titles.setting",
    ["dashboard/service_genres", "index"] => "drafity.dashboard.page_titles.service_genres",
    ["dashboard/service_genres", "new"] => "drafity.dashboard.page_titles.service_genres_new",
    ["dashboard/service_genres", "edit"] => "drafity.dashboard.page_titles.service_genres_edit",
    ["dashboard/clients", "api_settings"] => "drafity.dashboard.page_titles.api_settings",
    ["dashboard/clients", "my_api_settings"] => "drafity.dashboard.page_titles.api_settings",
    ["dashboard/api_guide", "show"] => "drafity.dashboard.page_titles.api_guide",
    ["dashboard/autonomous_runs", "index"] => "drafity.dashboard.page_titles.autonomous",
    ["dashboard/autonomous_runs", "new"] => "drafity.dashboard.page_titles.autonomous_new",
    ["dashboard/autonomous_runs", "show"] => "drafity.dashboard.page_titles.autonomous_show",
    ["dashboard/subscriptions", "show"] => "drafity.dashboard.page_titles.subscription",
    ["dashboard/subscriptions", "cancel_confirm"] => "drafity.dashboard.page_titles.subscription_cancel",
    ["admins/sessions", "new"] => "drafity.auth.meta_login_title",
    ["admins/registrations", "new"] => "drafity.auth.signup_title",
    ["admins/passwords", "new"] => "drafity.auth.meta_password_title",
    ["admins/passwords", "edit"] => "drafity.auth.meta_password_edit_title",
    ["clients/sessions", "new"] => "drafity.auth.login_title",
    ["clients/registrations", "new"] => "drafity.auth.signup_title"
  }.freeze

  def default_meta_tags
    {
      site: "豊富な人材集客力で企業の人材不足を解消|『J Work』",
      description: "豊富な人材集客力で企業の人材不足を解消|『J Work』。軽貨物・警備・建設・清掃業等様々な業界で活躍しています。",
      canonical: request.original_url,  # 優先されるurl
      charset: "UTF-8",
      reverse: true,
      separator: '|',
      icon: [
        { href: image_url('favicon.ico') },
        { href: image_url('favicon.ico'),  rel: 'apple-touch-icon' },
      ],

    }
  end

  def admin_page_title
    return content_for(:title).presence if content_for?(:title)

    key = [controller_path, action_name]

    case key
    when ["dashboard/clients", "api_settings"], ["dashboard/clients", "my_api_settings"]
      if defined?(@client) && @client&.email.present?
        t("drafity.dashboard.page_titles.with_suffix", name: @client.email, title: t("drafity.dashboard.page_titles.api_settings"))
      else
        t(ADMIN_PAGE_TITLE_KEYS.fetch(key))
      end
    when ["dashboard/service_genres", "edit"]
      if defined?(@service_genre) && @service_genre&.ja.present?
        t("drafity.dashboard.page_titles.with_suffix", name: @service_genre.ja, title: t("drafity.dashboard.page_titles.service_genres_edit"))
      else
        t(ADMIN_PAGE_TITLE_KEYS.fetch(key))
      end
    when ["dashboard/autonomous_runs", "show"]
      if defined?(@run) && @run&.title.present?
        t("drafity.dashboard.page_titles.with_suffix", name: @run.title, title: t("drafity.dashboard.page_titles.autonomous_show"))
      else
        t(ADMIN_PAGE_TITLE_KEYS.fetch(key))
      end
    when ["dashboard/subscriptions", "show"], ["dashboard/subscriptions", "cancel_confirm"]
      if defined?(@target_client) && @target_client&.email.present?
        "#{@target_client.email} - #{t(ADMIN_PAGE_TITLE_KEYS.fetch(key))}"
      else
        t(ADMIN_PAGE_TITLE_KEYS.fetch(key))
      end
    else
      ADMIN_PAGE_TITLE_KEYS.key?(key) ? t(ADMIN_PAGE_TITLE_KEYS.fetch(key)) : "Drafity Admin"
    end
  end

  def generation_mode_options_for_select(include_internal: admin_signed_in?)
    options = [[t("drafity.dashboard.generation_modes.default"), "default"], [t("drafity.dashboard.generation_modes.comparison"), "comparison"], [t("drafity.dashboard.generation_modes.recommendation"), "recommendation"]]
    return options unless include_internal

    options + [["Note", "note"], ["Qiita", "qiita"], ["Zenn", "zenn"]]
  end

  def generation_mode_label(mode)
    key = Column.normalize_generation_mode(mode)
    I18n.t("drafity.dashboard.generation_modes.#{key}", default: t("drafity.dashboard.generation_modes.default"))
  end

  def article_language_options_for_select
    [
      [t("drafity.columns.form.language_ja"), "ja"],
      [t("drafity.columns.form.language_en"), "en"]
    ]
  end

  def article_language_label(language)
    key = Column.normalize_language(language)
    t("drafity.columns.form.language_#{key}")
  end

  def column_content_locale(column)
    Column.english_language?(column&.language) ? :en : :ja
  end

  def default_article_language
    I18n.locale.to_s == "en" ? "en" : Column::DEFAULT_LANGUAGE
  end

  def service_genre_sub_category_items(service_genre)
    submitted = params.dig(:service_genre, :sub_categories_items)
    return normalize_sub_category_items(submitted) if submitted.present?

    service_genre.sub_categories_for_form
  end

  def normalize_sub_category_items(items)
    Array(items).map do |item|
      item = item.to_unsafe_h if item.respond_to?(:to_unsafe_h)
      item = item.with_indifferent_access
      {
        key: item[:key],
        name: item[:name],
        target: item[:target],
        description: item[:description],
        features_text: item[:features_text],
        keywords_text: item[:keywords_text],
        price_hint: item[:price_hint],
        area: item[:area],
        strengths: item[:strengths],
        industry_weakness: item[:industry_weakness]
      }
    end
  end

  def breadcrumb_list_json_ld
    return if !defined?(breadcrumbs) || breadcrumbs.blank?

    items = breadcrumbs.each_with_index.map do |crumb, i|
      item = {
        "@type" => "ListItem",
        "position" => i + 1,
        "name" => crumb[:label]
      }
      item["item"] = crumb[:path].present? ? "#{request.base_url}#{crumb[:path]}" : request.original_url
      item
    end

    {
      "@context" => "https://schema.org",
      "@type" => "BreadcrumbList",
      "itemListElement" => items
    }.to_json
  end

  # 記事詳細には英語版が無いので、トップ向けhreflangを出さない
  def public_column_article_page?
    controller_name == "columns" && action_name == "show" && !columns_manage_view?
  rescue StandardError
    false
  end

  def organization_json_ld
    {
      "@context" => "https://schema.org",
      "@type" => "Organization",
      "name" => "Drafity",
      "legalName" => "株式会社J Work",
      "url" => "https://drafity.pro/",
      "logo" => "https://drafity.pro#{image_path('favicon.ico')}",
      "description" => "AI記事生成SaaS「Drafity」の開発・提供。メディア支援・コンテンツマーケティング支援。",
      "address" => {
        "@type" => "PostalAddress",
        "streetAddress" => "浜松町２丁目２番１５号２Ｆ",
        "addressLocality" => "港区",
        "addressRegion" => "東京都",
        "addressCountry" => "JP"
      }
    }.to_json
  end

  def website_json_ld
    {
      "@context" => "https://schema.org",
      "@type" => "WebSite",
      "name" => "Drafity",
      "url" => "https://drafity.pro/",
      "inLanguage" => %w[ja en],
      "publisher" => {
        "@type" => "Organization",
        "name" => "株式会社J Work"
      }
    }.to_json
  end

  def faq_page_json_ld(items)
    entities = Array(items).filter_map do |item|
      q = (item[:q] || item["q"]).to_s.strip
      a = (item[:a] || item["a"]).to_s.strip
      next if q.blank? || a.blank?

      {
        "@type" => "Question",
        "name" => q,
        "acceptedAnswer" => {
          "@type" => "Answer",
          "text" => a
        }
      }
    end
    return if entities.blank?

    {
      "@context" => "https://schema.org",
      "@type" => "FAQPage",
      "mainEntity" => entities
    }.to_json
  end

  def english_ui?
    I18n.locale.to_s == "en"
  end

  def client_sign_in_path_for_locale
    english_ui? ? new_client_session_en_path(locale: :en) : new_client_session_path
  end

  def client_sign_up_path_for_locale
    english_ui? ? new_client_registration_en_path(locale: :en) : new_client_registration_path
  end

  def client_password_new_path_for_locale
    english_ui? ? new_client_password_en_path(locale: :en) : new_client_password_path
  end

  def client_session_url_for_locale
    english_ui? ? client_session_en_path(locale: :en) : session_path(:client)
  end

  def client_registration_url_for_locale
    english_ui? ? client_registration_en_path(locale: :en) : registration_path(:client)
  end

  def client_password_url_for_locale
    english_ui? ? client_password_en_path(locale: :en) : password_path(:client)
  end

  def client_password_update_url_for_locale
    english_ui? ? client_password_en_path(locale: :en) : password_path(:client)
  end

  def plans_path_for_locale
    english_ui? ? localized_plans_path(locale: :en) : plans_path
  end

  def select_plan_path_for_locale
    english_ui? ? localized_select_plan_path(locale: :en) : select_plan_path
  end

  def drafity_logo_image
    english_ui? ? "logo2-en.png" : "logo2.png"
  end
end
