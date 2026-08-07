# frozen_string_literal: true

class Clients::SessionsController < Devise::SessionsController
  layout "auth"

  def create
    self.resource = warden.authenticate!(auth_options)
    set_flash_message!(:notice, :signed_in)
    sign_in(resource_name, resource)
    session[:ui_locale] = resource.preferred_locale if resource.respond_to?(:preferred_locale)
    I18n.locale = resource.ui_locale if resource.respond_to?(:ui_locale)
    yield resource if block_given?
    respond_with resource, location: after_sign_in_path_for(resource)
  end

  protected

  def after_sign_out_path_for(_resource_or_scope)
    locale_root_href
  end
end
