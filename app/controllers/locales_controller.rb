class LocalesController < ApplicationController
  skip_before_action :check_trial_expiration

  def update
    locale = params[:locale].to_s
    unless Client::LOCALES.include?(locale)
      redirect_back fallback_location: root_path, alert: t("drafity.auth.invalid_locale", default: "Invalid language")
      return
    end

    session[:ui_locale] = locale
    cookies[:ui_locale] = {
      value: locale,
      expires: 1.year,
      path: "/",
      same_site: :lax
    }
    current_client.update(preferred_locale: locale) if client_signed_in?

    redirect_to locale_switch_destination(locale)
  end

  private

  def locale_switch_destination(locale)
    return_to = params[:return_to].to_s
    if return_to.present? && return_to.start_with?("/") && !return_to.start_with?("//")
      uri_path, query = return_to.split("?", 2)
      path = uri_path.sub(%r{\A/en(?=/|$)}, "")
      path = "/" if path.blank?

      # 管理用 /columns* は session locale で表示。EN希望なら公開ジャンルURLへは /en 付きへ
      if locale == "en" && manage_columns_path?(path)
        dest = path
      elsif locale == "en"
        dest = path == "/" ? "/en" : localize_public_path(path)
      else
        dest = path
      end
      return query.present? ? "#{dest}?#{query}" : dest
    end

    href_for_locale(locale.to_sym)
  end

  def manage_columns_path?(path)
    clean = path.to_s.split("?", 2).first.to_s
    clean == "/columns" || clean.start_with?("/columns/")
  end

  def localize_public_path(path)
    return "/en" if path == "/"
    return "/en#{path}" if public_locale_path?(path)

    path
  end

  def public_locale_path?(path)
    clean = path.to_s.split("?", 2).first.to_s
    clean == "/plans" ||
      clean.start_with?("/plans") ||
      clean == "/tops" ||
      clean.start_with?("/tops") ||
      clean == "/tools/seo-checker" ||
      clean.start_with?("/tools/seo-checker") ||
      clean.start_with?("/clients/sign_in") ||
      clean.start_with?("/clients/sign_up") ||
      clean.start_with?("/clients/password") ||
      public_genre_columns_path?(clean)
  end
end
