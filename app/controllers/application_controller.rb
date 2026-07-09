class ApplicationController < ActionController::Base
  include MetaTags::ControllerHelper

  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :check_trial_expiration

  before_action :init_breadcrumbs

  helper_method :breadcrumbs, :current_client_usage_summary

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