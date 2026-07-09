class ApplicationController < ActionController::Base
  include MetaTags::ControllerHelper

  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :check_trial_expiration

  before_action :init_breadcrumbs

  helper_method :breadcrumbs, :current_client_usage_summary, :can_manage_column?, :child_article_quota_for,
                :pillar_manage_path, :default_public_genre_key, :public_columns_index_path,
                :public_column_show_path

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
    Column.where("body IS NOT NULL AND TRIM(body) != ''")
  end

  def current_public_genre_key
    params[:genre].to_s.presence
  end

  def default_public_genre_key
    if client_signed_in?
      current_client.genre_keys.first
    elsif platform_host?(request.host)
      CrawlPolicy::GENRE_KEY
    else
      GenreRegistry.allowed_hosts(normalize_host(request.host))&.to_s
    end
  end

  def public_columns_index_path(extra_params = {})
    genre_key = extra_params[:genre].presence || default_public_genre_key
    return nil if genre_key.blank?

    columns_index_path({ genre: genre_key }.merge(extra_params.except(:genre)))
  end

  def public_column_show_path(column)
    return "#" unless column

    genre_key = GenreRegistry.resolve_key(column.genre) || column.genre.to_s
    columns_show_path(genre: genre_key, id: column.code.presence || column.id)
  end

  def accessible_public_genre?(genre_key)
    key = genre_key.to_s
    return false if key.blank?
    return false unless GenreRegistry.genre_keys.include?(key)

    if admin_signed_in?
      return true
    end

    if client_signed_in?
      return current_client.genre_keys.include?(key)
    end

    if platform_host?(request.host)
      return key == CrawlPolicy::GENRE_KEY
    end

    true
  end

  def public_readable_columns_scope
    genre_key = current_public_genre_key
    return Column.none if genre_key.blank?
    return Column.none unless accessible_public_genre?(genre_key)

    scope = published_columns_scope.where(genre: genre_key)

    owner_id = ServiceGenre.owner_client_id_for(genre_key)
    scope = scope.where(client_id: owner_id) if owner_id.present?

    if client_signed_in?
      scope = scope.where(client_id: current_client.id)
    end

    scope
  end

  def readable_column?(column)
    return false unless column

    genre_key = current_public_genre_key || column.genre.to_s
    return false if genre_key.blank?
    return false unless column.genre.to_s == genre_key
    return false unless accessible_public_genre?(genre_key)

    if client_signed_in?
      return column.client_id == current_client.id
    end

    return true if admin_signed_in?
    return false unless column.body.present?

    owner_id = ServiceGenre.owner_client_id_for(genre_key)
    return false if owner_id.present? && column.client_id != owner_id

    true
  end

  def platform_host?(host)
    %w[drafity.pro localhost 127.0.0.1].include?(normalize_host(host))
  end

  def normalize_host(host)
    host.to_s.downcase.sub(/\Awww\./, "").sub(/:\d+\z/, "")
  end

  def client_ids_for_host(host)
    normalized = normalize_host(host)
    return [] if normalized.blank?

    ServiceGenre.where.not(client_id: nil).find_each.filter_map do |genre|
      hosts = Array(genre.hosts).map { |entry| normalize_host(entry) }
      genre.client_id if hosts.include?(normalized)
    end.uniq
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