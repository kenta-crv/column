class ApplicationController < ActionController::Base
  include MetaTags::ControllerHelper
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :check_trial_expiration

  before_action :init_breadcrumbs
  helper_method :breadcrumbs


def current_client
    return @current_client if defined?(@current_client)
    return OpenStruct.new(expired?: false) if Rails.env.development?
    
    # 親クラスや包括モジュールに current_client が存在する場合のみ super を呼ぶ
    defined?(super) ? super : nil
  end

  def check_trial_expiration
    # current_client が nil、または OpenStruct などのオブジェクトでも安全に expired? を呼ぶ
    if current_client.respond_to?(:expired?) && current_client.expired?
      # 必要に応じて期限切れの処理（リダイレクトなど）をここに記述
    end
  end
  
  def breadcrumbs
    @breadcrumbs
  end

  def add_breadcrumb(label, path = nil)
    @breadcrumbs << { label: label, path: path }
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