class Dashboard::ClientsController < ApplicationController
  before_action :authenticate_admin_or_client!
  before_action :set_client, only: [:api_settings, :update_api_settings]
  before_action :ensure_own_client, only: [:api_settings, :update_api_settings], unless: :admin_signed_in?
  layout "admin"

  def api_settings
  end

  def my_api_settings
    @client = current_client
    render :api_settings
  end

  def update_api_settings
    allowed_genres = params[:client][:allowed_genres].present? ? params[:client][:allowed_genres].reject(&:blank?) : []

    embed_settings_raw = params[:client][:embed_settings]
    embed_settings = begin
      JSON.parse(embed_settings_raw)
    rescue
      {}
    end

    if @client.update(
      webhook_url: params[:client][:webhook_url],
      allowed_genres: allowed_genres,
      embed_settings: embed_settings
    )
      redirect_to (admin_signed_in? ? api_settings_dashboard_client_path(@client) : dashboard_api_settings_path), notice: "API設定を更新しました"
    else
      render :api_settings, alert: "更新に失敗しました"
    end
  end

  def update_my_api_settings
    @client = current_client
    allowed_genres = params[:client][:allowed_genres].present? ? params[:client][:allowed_genres].reject(&:blank?) : []

    embed_settings_raw = params[:client][:embed_settings]
    embed_settings = begin
      JSON.parse(embed_settings_raw)
    rescue
      {}
    end

    if @client.update(
      webhook_url: params[:client][:webhook_url],
      allowed_genres: allowed_genres,
      embed_settings: embed_settings
    )
      redirect_to dashboard_api_settings_path, notice: "API設定を更新しました"
    else
      render :api_settings, alert: "更新に失敗しました"
    end
  end

  private

  def set_client
    @client = Client.find(params[:id])
  end

  def ensure_own_client
    unless current_client == @client
      flash[:alert] = "自分の設定のみ変更できます。"
      redirect_to root_path
    end
  end

  def authenticate_admin_or_client!
    return if admin_signed_in?
    return if client_signed_in?

    flash[:alert] = "ログインが必要です。"
    redirect_to root_path
  end
end