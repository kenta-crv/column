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
    if admin_signed_in?
      redirect_to dashboard_root_path,
                  alert: t("drafity.auth.admin_session_blocks_client",
                           default: "管理者でログイン中です。企業アカウントの登録・ログインは、管理者をログアウトしてから行ってください。")
      return
    end

    auth = request.env["omniauth.auth"]
    locale = resolved_locale
    @client = Client.from_omniauth(auth, preferred_locale: locale)

    if @client.persisted?
      new_account = @client.previously_new_record?
      @client.initialize_trial_subscription! if @client.respond_to?(:initialize_trial_subscription!)
      sign_in @client, event: :authentication
      apply_saved_ui_locale!(@client)
      session.delete(:omniauth_locale)
      mark_yahoo_trial_conversion! if new_account
      set_flash_message(:notice, :success, kind: kind) if is_navigational_format?
      redirect_to after_sign_in_path_for(@client)
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
    origin = request.env["omniauth.origin"].to_s
    return "en" if origin.match?(%r{/en(/|\z)})

    omniauth_params = request.env["omniauth.params"] || {}
    param = (omniauth_params["locale"] || omniauth_params[:locale]).to_s
    return param if Client::LOCALES.include?(param)

    session_locale = session[:omniauth_locale].to_s
    return session_locale if Client::LOCALES.include?(session_locale)

    "ja"
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
