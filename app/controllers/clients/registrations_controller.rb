# frozen_string_literal: true

class Clients::RegistrationsController < Devise::RegistrationsController
  layout "auth"

  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [
      :company,
      :name,
      :tel,
      :address,
      :url,
      :preferred_locale
    ])
  end

  def configure_account_update_params
    devise_parameter_sanitizer.permit(:account_update, keys: [
      :company,
      :name,
      :tel,
      :address,
      :url,
      :preferred_locale
    ])
  end

  before_action :configure_sign_up_params, only: [:create]
  before_action :configure_account_update_params, only: [:update]

  def create
    build_resource(sign_up_params)
    resource.preferred_locale = resolved_signup_locale
    resource.save
    yield resource if block_given?
    if resource.persisted?
      session[:ui_locale] = resource.preferred_locale
      if resource.active_for_authentication?
        set_flash_message! :notice, :signed_up
        sign_up(resource_name, resource)
        respond_with resource, location: after_sign_up_path_for(resource)
      else
        set_flash_message! :notice, :"signed_up_but_#{resource.inactive_message}"
        expire_data_after_sign_in!
        respond_with resource, location: after_inactive_sign_up_path_for(resource)
      end
    else
      clean_up_passwords resource
      set_minimum_password_length
      respond_with resource
    end
  end

  def after_sign_up_path_for(_resource)
    dashboard_root_path
  end

  private

  def resolved_signup_locale
    locale = I18n.locale.to_s
    Client::LOCALES.include?(locale) ? locale : "ja"
  end
end
