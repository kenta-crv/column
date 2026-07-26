module ApplicationHelper
  ADMIN_PAGE_TITLES = {
    ["dashboard/columns", "index"] => "記事管理",
    ["dashboard/columns", "image_generation"] => "画像一括生成",
    ["dashboard/columns", "management"] => "クライアント管理",
    ["dashboard/columns", "setting"] => "設定",
    ["dashboard/service_genres", "index"] => "サービス・ジャンル管理",
    ["dashboard/service_genres", "new"] => "サービス・ジャンル作成",
    ["dashboard/service_genres", "edit"] => "サービス・ジャンル編集",
    ["dashboard/clients", "api_settings"] => "API設定",
    ["dashboard/clients", "my_api_settings"] => "API設定",
    ["dashboard/autonomous_runs", "index"] => "AI主導生成",
    ["dashboard/autonomous_runs", "new"] => "AI主導生成を開始",
    ["dashboard/autonomous_runs", "show"] => "AI主導生成詳細",
    ["dashboard/subscriptions", "show"] => "サブスクリプション管理",
    ["dashboard/subscriptions", "cancel_confirm"] => "サブスクリプション解約",
    ["admins/sessions", "new"] => "管理者ログイン",
    ["admins/registrations", "new"] => "管理者アカウント登録",
    ["admins/passwords", "new"] => "パスワード再設定",
    ["admins/passwords", "edit"] => "新しいパスワード",
    ["clients/sessions", "new"] => "ログイン",
    ["clients/registrations", "new"] => "アカウント登録"
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
        "#{@client.email} - API設定"
      else
        ADMIN_PAGE_TITLES.fetch(key)
      end
    when ["dashboard/service_genres", "edit"]
      if defined?(@service_genre) && @service_genre&.ja.present?
        "#{@service_genre.ja} - サービス・ジャンル編集"
      else
        ADMIN_PAGE_TITLES.fetch(key)
      end
    when ["dashboard/autonomous_runs", "show"]
      if defined?(@run) && @run&.title.present?
        "#{@run.title} - AI主導生成詳細"
      else
        ADMIN_PAGE_TITLES.fetch(key)
      end
    when ["dashboard/subscriptions", "show"], ["dashboard/subscriptions", "cancel_confirm"]
      if defined?(@target_client) && @target_client&.email.present?
        "#{@target_client.email} - #{ADMIN_PAGE_TITLES.fetch(key)}"
      else
        ADMIN_PAGE_TITLES.fetch(key)
      end
    else
      ADMIN_PAGE_TITLES.fetch(key, "Drafity Admin")
    end
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
end
