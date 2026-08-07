class LocalesController < ApplicationController
  skip_before_action :check_trial_expiration

  def update
    locale = params[:locale].to_s
    unless Client::LOCALES.include?(locale)
      redirect_back fallback_location: root_path, alert: t("drafity.auth.invalid_locale", default: "Invalid language")
      return
    end

    session[:ui_locale] = locale
    current_client.update(preferred_locale: locale) if client_signed_in?

    redirect_to locale_switch_destination(locale)
  end

  private

  def locale_switch_destination(locale)
    return_to = params[:return_to].to_s
    if return_to.present? && return_to.start_with?("/") && !return_to.start_with?("//")
      path = return_to.sub(%r{\A/en(?=/|$)}, "")
      path = "/" if path.blank?
      return locale == "en" ? (path == "/" ? "/en" : localize_public_path(path)) : path
    end

    href_for_locale(locale.to_sym)
  end

  def localize_public_path(path)
    return "/en" if path == "/"
    return "/en#{path}" if public_locale_path?(path)

    path
  end

  def public_locale_path?(path)
    path == "/plans" ||
      path.start_with?("/plans") ||
      path == "/tops" ||
      path.start_with?("/tops") ||
      path == "/tools/seo-checker" ||
      path.start_with?("/tools/seo-checker") ||
      path.start_with?("/clients/sign_in") ||
      path.start_with?("/clients/sign_up") ||
      path.start_with?("/clients/password")
  end
end
