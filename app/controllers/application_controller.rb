class ApplicationController < ActionController::Base
  include MetaTags::ControllerHelper

  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :check_trial_expiration

  before_action :init_breadcrumbs

  helper_method :breadcrumbs, :current_client_usage_summary, :can_manage_column?, :child_article_quota_for,
                :pillar_manage_path, :default_public_genre_key, :public_columns_index_path,
                :public_column_show_path, :columns_manage_view?, :sub_category_ui_config,
                :pending_review_columns_count, :routable_public_genre_key?, :platform_host?

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

  protected

  def authenticate_admin_or_client!
    return if admin_signed_in?
    return if client_signed_in?

    flash[:alert] = "ログインが必要です。"
    redirect_to root_path
  end

  def require_admin!
    return if admin_signed_in?

    flash[:alert] = "管理者権限が必要です。"
    redirect_to dashboard_root_path
  end

  def admin_or_allowed_genre?(genre)
    return true if admin_signed_in?

    current_client_allowed_genre_keys.include?(genre.to_s)
  end

  def dashboard_columns_base_scope
    if admin_signed_in?
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

    dashboard_columns_base_scope.merge(Column.pending_review).count
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

    columns_index_path({ genre: genre_key }.merge(extras))
  rescue ActionController::UrlGenerationError
    columns_manage_view? ? columns_path(extras) : nil
  end

  def public_column_show_path(column)
    return "#" unless column

    # 管理画面では公開用ジャンル制約ルートを使わず、通常の columns リソースへ戻す
    return column_path(column) if columns_manage_view?

    genre_key = (GenreRegistry.resolve_key(column.genre, client: column.client) || column.genre).to_s
    return column_path(column) unless routable_public_genre_key?(genre_key)

    columns_show_path(genre: genre_key, id: column.code.presence || column.id)
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

    if admin_signed_in?
      return true if GenreRegistry.genre_keys.include?(key)
      return ServiceGenre.exists?(key: key)
    end

    if client_signed_in?
      allowed = Array(current_client.allowed_genres).map(&:to_s)
      return allowed.include?(key) if allowed.present?

      return current_client.genre_keys.include?(key)
    end

    # 公開SSRはジャンルが実在すれば表示する。
    # drafity.pro で ai_article 以外をここで落とすと、
    # 自社ドメインが Host: drafity.pro 経由で来た場合に cleaning 等が 0 件になる。
    # Google への公開範囲制限は robots.txt / CrawlPolicy 側で行う。
    return true if key == CrawlPolicy::GENRE_KEY
    return true if GenreRegistry.genre_keys.include?(key)
    return true if ServiceGenre.registered_key?(key)

    false
  end

  def columns_manage_view?
    admin_signed_in? || client_signed_in?
  end

  def public_genre_filter_values(genre_key, client: nil)
    return [] if genre_key.blank?

    key = genre_key.to_s
    registry = client ? GenreRegistry.genres(client: client) : GenreRegistry.genres
    entry = registry[key.to_sym]
    ja = entry&.dig(:ja) || GenreRegistry.to_ja(key, client: client)
    [key, ja].compact.uniq.reject(&:blank?)
  end

  def column_matches_genre?(column, genre_key)
    return true if genre_key.blank?

    client = column&.client
    client ||= current_client if client_signed_in?
    public_genre_filter_values(genre_key, client: client).include?(column.genre.to_s)
  end

  def columns_list_scope
    genre_key = current_public_genre_key.presence || default_public_genre_key
    client = current_client if client_signed_in?

    if client_signed_in?
      genre_values = public_genre_filter_values(genre_key, client: client)
      scope = Column.where(client_id: client.id)
      scope = scope.where(genre: genre_values) if genre_values.present?

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

    if admin_signed_in?
      return dashboard_columns_base_scope if genre_key.blank?

      genre_values = public_genre_filter_values(genre_key)
      scope = dashboard_columns_base_scope
      scope = scope.where(genre: genre_values) if genre_values.present?

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
    published_columns_scope.where(genre: genre_values.presence || genre_key)
  end

  def public_readable_columns_scope
    columns_list_scope
  end

  def readable_column?(column)
    return false unless column

    genre_key = current_public_genre_key.presence || default_public_genre_key

    if columns_manage_view?
      return column.client_id == current_client.id if client_signed_in?
      return true if admin_signed_in?
    end

    return false if genre_key.blank?
    return false unless column_matches_genre?(column, genre_key)
    return false unless accessible_public_genre?(genre_key)

    if client_signed_in?
      return column.client_id == current_client.id
    end

    return true if admin_signed_in?

    # 公開詳細も Client 絞り込みしない（自社ドメインの従来仕様）
    column.publicly_visible?
  end

  def platform_host?(host)
    %w[drafity.pro localhost 127.0.0.1].include?(normalize_host(host))
  end

  def normalize_host(host)
    host.to_s.downcase.sub(/\Awww\./, "").sub(/:\d+\z/, "")
  end

  def can_manage_column?(column)
    return false unless column

    admin_signed_in? || (client_signed_in? && column.client_id == current_client.id)
  end

  def child_article_quota_for(column)
    return nil unless can_manage_column?(column)

    owner = column.client
    if owner
      limit = owner.plan_limits[:child_articles]
      used = owner.child_usage_count
    else
      limit = column.cluster_limit.presence || 25
      used = column.children.count
    end

    remaining = remaining_child_slots_for(column)
    { used: used, limit: limit, remaining: remaining }
  end

  def pillar_manage_path(column)
    return column_path(column) if columns_manage_view?

    public_column_show_path(column)
  end

  def remaining_child_slots_for(column)
    owner = column.client

    if owner
      remaining = owner.plan_limits[:child_articles] - owner.child_usage_count
      if column.cluster_limit.present?
        remaining = [remaining, column.cluster_limit - column.children.count].min
      end
      [remaining, 0].max
    else
      cap = column.cluster_limit.presence || 25
      [cap - column.children.count, 0].max
    end
  end

  def current_client_allowed_genre_keys
    return [] unless client_signed_in?

    current_client.genre_keys
  end

  def client_accessible_genre_registry
    return GenreRegistry.genres unless client_signed_in?

    GenreRegistry.genres(client: current_client)
  end

  def dashboard_genre_registry_options
    registry = if admin_signed_in?
                 GenreRegistry.genres
               else
                 client_accessible_genre_registry
               end

    registry.map { |key, value| [value[:ja], key.to_s] }
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
    if admin_signed_in?
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
      dashboard_root_path
    when Client
      dashboard_root_path
    else
      root_path
    end
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

  private

  def admin_root_path
    admin_dashboard_index_path
  end

  def init_breadcrumbs
    @breadcrumbs = []
  end
end