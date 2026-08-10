# frozen_string_literal: true

class Clients::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def google_oauth2
    handle_auth("Google")
  end

  def microsoft_graph
    handle_auth("Microsoft")
  end

  def failure
    redirect_to client_sign_in_path_for_oauth_locale,
                alert: t("drafity.auth.oauth_failure", default: "外部アカウントでのログインに失敗しました。")
  end

  private

  def handle_auth(kind)
    auth = request.env["omniauth.auth"]
    locale = resolved_locale
    @client = Client.from_omniauth(auth, preferred_locale: locale)

    if @client.persisted?
      @client.initialize_trial_subscription! if @client.respond_to?(:initialize_trial_subscription!)
      session[:ui_locale] = @client.preferred_locale if @client.preferred_locale.present?
      session.delete(:omniauth_locale)
      sign_in_and_redirect @client, event: :authentication
      set_flash_message(:notice, :success, kind: kind) if is_navigational_format?
    else
      session["devise.#{auth.provider}_data"] = auth.except("extra")
      redirect_to client_sign_up_path_for_oauth_locale,
                  alert: @client.errors.full_messages.to_sentence.presence ||
                         t("drafity.auth.oauth_failure", default: "外部アカウントでのログインに失敗しました。")
    end
  rescue ArgumentError => e
    redirect_to client_sign_in_path_for_oauth_locale,
                alert: e.message.presence || t("drafity.auth.oauth_failure", default: "外部アカウントでのログインに失敗しました。")
  end

  def resolved_locale
    candidates = [
      session[:omniauth_locale],
      session[:ui_locale],
      I18n.locale.to_s
    ].map { |v| v.to_s.presence }.compact
    candidates.find { |locale| Client::LOCALES.include?(locale) } || "ja"
  end

  def client_sign_in_path_for_oauth_locale
    resolved_locale == "en" ? new_client_session_en_path(locale: :en) : new_client_session_path
  end

  def client_sign_up_path_for_oauth_locale
    resolved_locale == "en" ? new_client_registration_en_path(locale: :en) : new_client_registration_path
  end

  def after_sign_in_path_for(_resource)
    dashboard_root_path
  end
end
