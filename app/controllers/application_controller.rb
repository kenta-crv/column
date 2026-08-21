class ApplicationController < ActionController::Base
  include MetaTags::ControllerHelper

  layout :layout_for_request

  before_action :set_locale
  before_action :stash_omniauth_locale
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :check_trial_expiration
  before_action :init_breadcrumbs

  helper_method :breadcrumbs, :current_client_usage_summary, :can_manage_column?, :child_article_quota_for,
                :pillar_manage_path, :default_public_genre_key, :public_columns_index_path,
                :public_column_show_path, :columns_manage_view?, :sub_category_ui_config,
                :pending_review_columns_count, :missing_image_columns_count,
                :routable_public_genre_key?, :platform_host?, :acting_as_admin?,
                :public_request_host, :current_locale, :locale_root_href, :href_for_locale, :available_ui_locales, :locale_switch_path_for,
                :yahoo_trial_conversion_pending?

  def check_trial_expiration
    return unless current_client.present?
    current_client.check_and_upgrade_expired_trial
  end

  def breadcrumbs
    @breadcrumbs
  end

  def add_breadcrumb(label, path = nil)
    @breadcrumbs << { label: label, path: path }
  end

  def current_locale
    I18n.locale
  end

  def available_ui_locales
    %i[ja en]
  end

  def locale_root_href
    if I18n.locale.to_s == "en"
      localized_root_path(locale: :en)
    else
      root_path
    end
  end

  # 公開ページは / <-> /en。認証・plans も同様。それ以外は locale 切替エンドポイントへ。
  # *_path 名は Rails のルートヘルパーと衝突するため使わない。
  def href_for_locale(target_locale)
    target = target_locale.to_s
    return locale_root_href if target.blank?

    path = request.path.to_s.sub(%r{\A/en(?=/|$)}, "")
    path = "/" if path.blank?

    if public_switchable_path?(path)
      target == "ja" ? path : (path == "/" ? "/en" : "/en#{path}")
    else
      locale_switch_path_for(target, return_to: request.fullpath)
    end
  end

  def locale_switch_path_for(target_locale, return_to: nil)
    switch_locale_path(locale: target_locale, return_to: return_to.presence || request.fullpath)
  end

  protected

  def set_locale
    locale = resolve_ui_locale
    I18n.locale = locale
    # 公開URLの表示言語はダッシュボード言語（session / preferred_locale）を上書きしない
    return if public_switchable_path?(request_path_without_locale)

    persist_ui_locale!(locale)
  end

  # OAuth は /clients/auth/*（/en 外）へ飛ぶため、開始時点の UI locale を session に残す
  def stash_omniauth_locale
    return unless request.path.to_s.start_with?("/clients/auth/")
    return if request.path.to_s.include?("/callback")

    locale = params[:locale].presence.to_s
    locale = session[:omniauth_locale].to_s unless Client::LOCALES.include?(locale)
    locale = auth_url_locale unless Client::LOCALES.include?(locale)
    session[:omniauth_locale] = locale if Client::LOCALES.include?(locale)
  end

  # 認証画面の言語は URL（/en なら英語、それ以外は日本語）。古い cookie は使わない。
  def auth_url_locale
    return "en" if params[:locale].to_s == "en"
    return "en" if request.path.to_s.match?(%r{\A/en(/|\z)})

    "ja"
  end

  def persist_ui_locale!(locale)
    value = locale.to_s
    return unless Client::LOCALES.include?(value)

    session[:ui_locale] = value
    cookies[:ui_locale] = {
      value: value,
      expires: 1.year,
      path: "/",
      same_site: :lax
    }
  end

  def adopt_request_locale!(client, locale: I18n.locale)
    value = locale.to_s
    return unless client && Client::LOCALES.include?(value)

    persist_ui_locale!(value)
    client.update(preferred_locale: value) if client.preferred_locale != value
    I18n.locale = value.to_sym
  end

  # ユーザーが選んでいるUI言語（パス強制の影響を受けない）
  def preferred_ui_locale
    if client_signed_in? && current_client.preferred_locale.present?
      return current_client.ui_locale
    end

    session_locale = session[:ui_locale].to_s
    return session_locale.to_sym if Client::LOCALES.include?(session_locale)

    cookie_locale = cookies[:ui_locale].to_s
    return cookie_locale.to_sym if Client::LOCALES.include?(cookie_locale)

    :ja
  end

  def resolve_ui_locale
    requested = params[:locale].presence.to_s
    return requested.to_sym if Client::LOCALES.include?(requested)

    # /en なしの公開URLは日本語表示。アカウント言語はログイン時・言語切替時に合わせる
    path = request_path_without_locale
    return :ja if public_switchable_path?(path)

    preferred_ui_locale
  end

  def request_path_without_locale
    path = request.path.to_s.sub(%r{\A/en(?=/|$)}, "")
    path = "/" if path.blank?
    path
  end


  def public_switchable_path?(path)
    path == "/" ||
      path == "/plans" ||
      path.start_with?("/plans") ||
      path == "/tops" ||
      path.start_with?("/tops") ||
      path == "/tools/seo-checker" ||
      path.start_with?("/tools/seo-checker") ||
      path.start_with?("/clients/sign_in") ||
      path.start_with?("/clients/sign_up") ||
      path.start_with?("/clients/password") ||
      path.start_with?("/clients/auth") ||
      (path == "/clients" && !client_signed_in?) ||
      public_genre_columns_path?(path)
  end

  # /ai_article/columns など公開記事一覧・詳細。
  # /dashboard/columns は管理画面なので除外する（生成ポーリングやレビュー待ちタブで
  # ダッシュボードが日本語に上書きされるのを防ぐ）。
  NON_PUBLIC_GENRE_SEGMENTS = %w[
    dashboard columns clients admins locale checkout plans tops tools
    problems contracts draft webhooks sidekiq rails assets api
  ].freeze

  def public_genre_columns_path?(path)
    clean = path.to_s.split("?", 2).first.to_s
    match = clean.match(%r{\A/([a-z0-9_]+)/columns(?:/|\z)})
    return false unless match

    !NON_PUBLIC_GENRE_SEGMENTS.include?(match[1])
  end

  def acting_as_admin?
    admin_signed_in? && !client_signed_in?
  end

  def reject_client_auth_while_admin!
    return unless admin_signed_in?

    redirect_to dashboard_root_path,
                alert: t("drafity.auth.admin_session_blocks_client",
                         default: "管理者でログイン中です。企業アカウントの登録・ログインは、管理者をログアウトしてから行ってください。")
  end

  def authenticate_admin_or_client!
    return if acting_as_admin?
    return if client_signed_in?

    if request.get?
      store_location_for(:client, request.fullpath)
      store_location_for(:admin, request.fullpath)
    end

    redirect_to unauthenticated_session_path, alert: t("drafity.auth.login_required")
  end

  def require_admin!
    return if acting_as_admin?

    flash[:alert] = t("drafity.dashboard.flashes.admin_required")
    redirect_to dashboard_root_path
  end

  def admin_or_allowed_genre?(genre)
    return true if acting_as_admin?
    return false if genre.blank?

    equivalent = GenreRegistry.equivalent_keys(genre)
    equivalent.any? { |k| current_client_allowed_genre_keys.include?(k) }
  end

  def dashboard_columns_base_scope
    if acting_as_admin?
      Column.all
    elsif client_signed_in?
      Column.where(client_id: current_client.id)
    else
      Column.none
    end
  end

  def published_columns_scope
    Column.published.merge(Column.with_generated_body)
  end

  # サイドバーの「レビュー待ち」バッジなど、画面全体で使う未公開の生成済み記事数。
  def pending_review_columns_count
    return 0 unless admin_signed_in? || client_signed_in?
    return @pending_review_columns_count if defined?(@pending_review_columns_count) && !@pending_review_columns_count.nil?

    @pending_review_columns_count = Rails.cache.fetch(sidebar_column_count_cache_key("pending_review"), expires_in: 45.seconds) do
      dashboard_columns_base_scope.merge(Column.pending_review).count
    end
  end

  # サイドバーの「画像一括生成」バッジ用。レビュー待ちかつ画像未設定の記事数。
  def missing_image_columns_count
    return 0 unless admin_signed_in? || client_signed_in?
    return @missing_image_columns_count if defined?(@missing_image_columns_count) && !@missing_image_columns_count.nil?

    @missing_image_columns_count = Rails.cache.fetch(sidebar_column_count_cache_key("missing_image_v2"), expires_in: 45.seconds) do
      dashboard_columns_base_scope.merge(Column.pending_review_missing_image).count
    end
  end

  def sidebar_column_count_cache_key(kind)
    actor = Column.sidebar_column_count_actor_key(
      admin: acting_as_admin?,
      client_id: client_signed_in? ? current_client.id : nil
    )
    version = Column.sidebar_column_count_cache_version(actor)
    "sidebar_column_count:#{kind}:#{actor}:v#{version}"
  end

  def current_public_genre_key
    params[:genre].to_s.presence
  end

  def default_public_genre_key
    if client_signed_in?
      Array(current_client.allowed_genres).map(&:to_s).reject(&:blank?).first ||
        current_client.genre_keys.first
    elsif platform_host?(request.host)
      CrawlPolicy::GENRE_KEY
    else
      GenreRegistry.allowed_hosts(normalize_host(request.host))&.to_s
    end
  end

  def public_columns_index_path(extra_params = {})
    genre_key = (extra_params[:genre].presence || default_public_genre_key).to_s
    extras = extra_params.except(:genre)

    if genre_key.blank? || !routable_public_genre_key?(genre_key)
      return columns_path(extras) if columns_manage_view?

      return nil
    end

    route_params = { genre: genre_key }.merge(extras)
    if I18n.locale.to_s == "en"
      localized_columns_index_path(route_params.merge(locale: :en))
    else
      columns_index_path(route_params)
    end
  rescue ActionController::UrlGenerationError
    columns_manage_view? ? columns_path(extras) : nil
  end

  def public_column_show_path(column, locale: I18n.locale)
    return "#" unless column

    # 管理画面では公開用ジャンル制約ルートを使わず、通常の columns リソースへ戻す
    return column_path(column) if columns_manage_view?

    genre_key = (GenreRegistry.resolve_key(column.genre, client: column.client) || column.genre).to_s
    return column_path(column) unless routable_public_genre_key?(genre_key)

    id = column.code.presence || column.id
    if locale.to_s == "en"
      localized_columns_show_path(locale: :en, genre: genre_key, id: id)
    else
      columns_show_path(genre: genre_key, id: id)
    end
  rescue ActionController::UrlGenerationError
    column_path(column)
  end

  def routable_public_genre_key?(genre_key)
    genre_key.to_s.match?(/\A[a-z0-9_]+\z/)
  end

  def accessible_public_genre?(genre_key)
    key = genre_key.to_s
    return true if key.blank? && (admin_signed_in? || client_signed_in?)
    return false if key.blank?

    equivalent = GenreRegistry.equivalent_keys(key)

    if columns_manage_view?
      if acting_as_admin?
        return true if equivalent.any? { |k| GenreRegistry.genre_keys.include?(k) }
        return true if equivalent.any? { |k| ServiceGenre.exists?(key: k) }
        return false
      end

      if client_signed_in?
        allowed = Array(current_client.allowed_genres).map(&:to_s)
        if allowed.present?
          return equivalent.any? { |k| allowed.include?(k) }
        end

        return equivalent.any? { |k| current_client.genre_keys.include?(k) }
      end
    end

    # 公開URLはログイン中でも公開判定（管理画面のみクライアント制限）
    return true if equivalent.include?(CrawlPolicy::GENRE_KEY)
    return true if equivalent.any? { |k| GenreRegistry.genre_keys.include?(k) }
    return true if equivalent.any? { |k| ServiceGenre.registered_key?(k) }

    false
  end

  def columns_manage_view?
    return false unless admin_signed_in? || client_signed_in?

    # /:genre/columns と /en/:genre/columns は公開表示（言語フィルタ対象）
    params[:genre].blank?
  end

  def public_genre_filter_values(genre_key, client: nil)
    return [] if genre_key.blank?

    key = genre_key.to_s
    keys = GenreRegistry.equivalent_keys(key)
    canonical = GenreRegistry.canonical_key(key)
    registry = client ? GenreRegistry.genres(client: client) : GenreRegistry.genres
    entry = registry[canonical.to_sym] || registry[key.to_sym]
    ja = entry&.dig(:ja) || GenreRegistry.to_ja(key, client: client)
    (keys + [ja]).compact.uniq.reject(&:blank?)
  end

  def merge_canonical_genre_counts(counts)
    counts.each_with_object(Hash.new(0)) do |(key, count), result|
      canon = GenreRegistry.canonical_key(key).presence || key.to_s
      result[canon] += count.to_i
    end
  end

  def column_matches_genre?(column, genre_key)
    return true if genre_key.blank?

    client = column&.client
    client ||= current_client if client_signed_in?
    public_genre_filter_values(genre_key, client: client).include?(column.genre.to_s)
  end

  def columns_list_scope
    # 管理画面（/columns）では明示の genre 指定がない限り全件。
    # default_public_genre_key（drafity.pro では ai_article）を当てると
    # Admin が自社ジャンル以外を見失うため、公開一覧専用のデフォルトに限定する。
    manage_view = columns_manage_view?
    genre_key = current_public_genre_key.presence
    genre_key ||= default_public_genre_key unless manage_view
    client = current_client if client_signed_in?

    if manage_view && client_signed_in?
      scope = Column.where(client_id: client.id)
      if genre_key.present?
        genre_values = public_genre_filter_values(genre_key, client: client)
        scope = scope.where(genre: genre_values) if genre_values.present?
      end

      case params[:article_type].to_s
      when "pillar"
        scope = scope.where(article_type: "pillar")
      when "child"
        scope = scope.where(article_type: %w[child cluster])
        scope = scope.merge(published_columns_scope)
      else
        scope = scope.merge(published_columns_scope)
      end

      return scope
    end

    if manage_view && acting_as_admin?
      scope = dashboard_columns_base_scope
      if genre_key.present?
        genre_values = public_genre_filter_values(genre_key)
        scope = scope.where(genre: genre_values) if genre_values.present?
      end

      case params[:article_type].to_s
      when "pillar"
        scope = scope.where(article_type: "pillar")
      when "child"
        scope = scope.where(article_type: %w[child cluster]).merge(published_columns_scope)
      else
        scope = scope.merge(published_columns_scope)
      end

      return scope
    end

    return Column.none if genre_key.blank?
    return Column.none unless accessible_public_genre?(genre_key)

    # 自社ドメイン公開は Client 無関係。ジャンル + 公開済みのみで出す。
    genre_values = public_genre_filter_values(genre_key)
    published_columns_scope.where(genre: genre_values.presence || genre_key).merge(Column.for_ui_locale)
  end

  def public_readable_columns_scope
    columns_list_scope
  end

  def readable_column?(column)
    return false unless column

    genre_key = current_public_genre_key.presence || default_public_genre_key

    if columns_manage_view?
      return column.client_id == current_client.id if client_signed_in?
      return true if acting_as_admin?
    end

    return false if genre_key.blank?
    return false unless column_matches_genre?(column, genre_key)
    return false unless accessible_public_genre?(genre_key)

    column.publicly_visible?
  end

  def platform_host?(host = nil)
    # ブランドnginxは Host: drafity.pro でプロキシすることがあるため、
    # ブラウザ側ホスト（X-Forwarded-Host）を優先して判定する。
    candidate = if host.nil? || normalize_host(host) == "drafity.pro"
                  public_request_host
                else
                  normalize_host(host)
                end

    %w[drafity.pro localhost 127.0.0.1].include?(candidate)
  end

  def public_request_host
    forwarded = request.headers["X-Forwarded-Host"].to_s.split(",").first.to_s.strip.presence
    normalize_host(forwarded || request.host)
  end

  def normalize_host(host)
    host.to_s.downcase.sub(/\Awww\./, "").sub(/:\d+\z/, "")
  end

  def can_manage_column?(column)
    return false unless column

    acting_as_admin? || (client_signed_in? && column.client_id == current_client.id)
  end

  def child_article_quota_for(column)
    return nil unless can_manage_column?(column)

    owner = column.client
    children_used = children_count_for(column)
    if owner
      limit = owner.plan_limits[:child_articles]
      used = owner.child_usage_count
    else
      limit = column.cluster_limit.presence || 25
      used = children_used
    end

    remaining = remaining_child_slots_for(column, children_used: children_used)
    { used: used, limit: limit, remaining: remaining }
  end

  def pillar_manage_path(column)
    return column_path(column) if columns_manage_view?

    public_column_show_path(column)
  end

  def remaining_child_slots_for(column, children_used: nil)
    owner = column.client
    children_used = children_count_for(column) if children_used.nil?

    if owner
      remaining = owner.plan_limits[:child_articles] - owner.child_usage_count
      if column.cluster_limit.present?
        remaining = [remaining, column.cluster_limit - children_used].min
      end
      [remaining, 0].max
    else
      cap = column.cluster_limit.presence || 25
      [cap - children_used, 0].max
    end
  end

  def children_count_for(column)
    @children_count_by_parent_id ||= {}
    @children_count_by_parent_id[column.id] ||= column.children.count
  end

  def current_client_allowed_genre_keys
    return [] unless client_signed_in?

    current_client.genre_keys
  end

  def client_accessible_genre_registry
    return GenreRegistry.genres unless client_signed_in?

    GenreRegistry.genres(client: current_client)
  end

  def dashboard_genre_registry
    if acting_as_admin?
      GenreRegistry.genres
    else
      client_accessible_genre_registry
    end
  end

  def dashboard_genre_registry_options
    dashboard_genre_registry.map { |key, _value|
      [GenreRegistry.label_for(key, locale: I18n.locale), key.to_s]
    }
  end

  def dashboard_sub_categories_json
    localized_sub_categories_json(dashboard_genre_registry)
  end

  def localized_sub_categories_json(registry, locale: I18n.locale)
    english = locale.to_s == "en"
    registry.each_with_object({}) do |(genre_key, value), acc|
      acc[genre_key] = (value[:sub_categories] || {}).map do |sub_key, sub_value|
        name = if sub_value.is_a?(Hash)
                 if english
                   sub_value[:name_en].presence || sub_value["name_en"].presence ||
                     sub_value[:name].presence || sub_value["name"].presence || sub_key.to_s
                 else
                   sub_value[:name].presence || sub_value["name"].presence ||
                     sub_value[:name_en].presence || sub_value["name_en"].presence || sub_key.to_s
                 end
               else
                 sub_key.to_s
               end
        { id: sub_key.to_s, name: name }
      end
    end.to_json
  end

  def assign_column_client!(column)
    return unless client_signed_in?
    return if column.client_id.present?

    column.client_id = current_client.id
  end

  def current_client_usage_summary
    return nil unless client_signed_in?

    current_client.usage_summary
  end

  def sub_category_ui_config
    if acting_as_admin?
      {
        allowed: true,
        unlimited: true,
        max: Subscription::PLANS.values.map { |plan| plan[:sub_category_count].to_i }.max,
        default: 1
      }
    elsif client_signed_in?
      max = current_client.max_sub_category_count
      {
        allowed: max.positive?,
        unlimited: false,
        max: max,
        default: 1
      }
    else
      { allowed: false, unlimited: false, max: 0, default: 0 }
    end
  end

  def after_sign_in_path_for(resource)
    case resource
    when Admin
      sign_out(:client) if client_signed_in?
      stored_location_for(:admin).presence || dashboard_root_path
    when Client
      stored_location_for(:client).presence || dashboard_root_path
    else
      locale_root_href
    end
  end

  def after_sign_out_path_for(_resource_or_scope)
    locale_root_href
  end

  def mark_yahoo_trial_conversion!
    session[:yahoo_ads_trial_cv] = true
  end

  def yahoo_trial_conversion_pending?
    session.delete(:yahoo_ads_trial_cv).present?
  end

  def configure_permitted_parameters
    added_attrs = [
      :first_name,
      :last_name,
      :email,
      :password,
      :password_confirmation,
      :remember_me
    ]

    devise_parameter_sanitizer.permit(:sign_up, keys: added_attrs)
    devise_parameter_sanitizer.permit(:account_update, keys: added_attrs)
  end

  def layout_for_request
    return "auth" if devise_controller? && !admin_controller?

    "application"
  end

  def authenticate_client!
    unless client_signed_in?
      respond_to do |format|
        format.json { render json: { error: "Unauthorized" }, status: :unauthorized }
        format.all do
          store_location_for(:client, request.fullpath) if request.get?
          redirect_to unauthenticated_session_path, alert: t("drafity.auth.login_required")
        end
      end
    end
  end

  def unauthenticated_session_path
    if request.path.start_with?("/admins")
      new_admin_session_path
    elsif I18n.locale.to_s == "en"
      new_client_session_en_path(locale: :en)
    else
      new_client_session_path
    end
  end

  private

  def admin_controller?
    is_a?(::AdminsController) || self.class.name.start_with?("Admins::") || self.class.name.start_with?("Dashboard::")
  end

  def admin_root_path
    admin_dashboard_index_path
  end

  def init_breadcrumbs
    @breadcrumbs = []
  end
end