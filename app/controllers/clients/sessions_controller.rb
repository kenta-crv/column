# frozen_string_literal: true

class Clients::SessionsController < Devise::SessionsController
  layout "auth"

  before_action :reject_client_auth_while_admin!, only: [:new, :create]

  def new
    session[:omniauth_locale] = auth_url_locale
    super
  end

  def create
    self.resource = warden.authenticate!(auth_options)
    set_flash_message!(:notice, :signed_in)
    sign_in(resource_name, resource)
    apply_saved_ui_locale!(resource)
    yield resource if block_given?
    respond_with resource, location: after_sign_in_path_for(resource)
  end

  protected

  def after_sign_out_path_for(_resource_or_scope)
    locale_root_href
  end
end
