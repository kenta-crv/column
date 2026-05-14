class ApplicationController < ActionController::Base
  include MetaTags::ControllerHelper
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :check_trial_expiration
  before_action :set_robots_meta

  before_action :init_breadcrumbs
  helper_method :breadcrumbs


    def current_client
    return @current_client if defined?(@current_client)
    return OpenStruct.new(expired?: false) if Rails.env.development?
    super
  end

  def check_trial_expiration
    return if Rails.env.development?  # 開発環境ではスキップ
    if current_client.expired?
      redirect_to expired_path
    end
  end

  def breadcrumbs
    @breadcrumbs
  end

  def add_breadcrumb(label, path = nil)
    @breadcrumbs << { label: label, path: path }
  end

  def set_robots_meta
  host = request.host

  if host == "column.okey.work"
    @robots_content = "noindex, nofollow"
  else
    @robots_content = "index, follow"
  end
end

  protected
def after_sign_in_path_for(resource)
  if resource.is_a?(Admin)
    # Admin用のダッシュボードがないようなので、一旦 root か columns 一覧へ
    return root_path
  end

  if resource.is_a?(Client)
    # routesにある「clients GET /clients(.:format)」を参照
    return clients_path
  end

  super
end

  def configure_permitted_parameters
    added_attrs = [:first_name, :last_name, :email, :password, :password_confirmation, :remember_me]
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