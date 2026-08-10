class Dashboard::ClientsController < ApplicationController
  before_action :authenticate_admin_or_client!
  before_action :set_client, only: [:api_settings, :update_api_settings, :regenerate_api_key]
  before_action :set_own_client, only: [:my_api_settings, :update_my_api_settings, :regenerate_my_api_key]
  before_action :ensure_own_client, only: [:api_settings, :update_api_settings, :regenerate_api_key], unless: :admin_signed_in?
  before_action :assign_client_genre_options, only: [:api_settings, :my_api_settings, :update_api_settings, :update_my_api_settings]
  layout "admin"

  def api_settings
  end

  def my_api_settings
    render :api_settings
  end

  def update_api_settings
    embed_settings_raw = params[:client][:embed_settings]
    embed_settings = begin
      JSON.parse(embed_settings_raw)
    rescue
      {}
    end

    if @client.update(
      webhook_url: params[:client][:webhook_url],
      embed_settings: embed_settings
    )
      redirect_to (admin_signed_in? ? api_settings_dashboard_client_path(@client) : dashboard_api_settings_path), notice: t("drafity.dashboard.flashes.api_updated")
    else
      render :api_settings, alert: t("drafity.dashboard.flashes.api_update_failed")
    end
  end

  def update_my_api_settings
    embed_settings_raw = params[:client][:embed_settings]
    embed_settings = begin
      JSON.parse(embed_settings_raw)
    rescue
      {}
    end

    if @client.update(
      webhook_url: params[:client][:webhook_url],
      embed_settings: embed_settings
    )
      redirect_to dashboard_api_settings_path, notice: t("drafity.dashboard.flashes.api_updated")
    else
      render :api_settings, alert: t("drafity.dashboard.flashes.api_update_failed")
    end
  end

  def regenerate_api_key
    @client.regenerate_api_key!
    redirect_to api_settings_dashboard_client_path(@client), notice: t("drafity.dashboard.flashes.api_key_regenerated")
  end

  def regenerate_my_api_key
    @client.regenerate_api_key!
    redirect_to dashboard_api_settings_path, notice: t("drafity.dashboard.flashes.api_key_regenerated")
  end

  private

  def assign_client_genre_options
    return unless @client

    @client_service_genres = @client.service_genres.order(:ja)
  end

  def set_client
    @client = Client.find(params[:id])
  end

  def set_own_client
    @client = current_client
  end

  def ensure_own_client
    unless current_client == @client
      flash[:alert] = t("drafity.dashboard.flashes.own_settings_only")
      redirect_to root_path
    end
  end
end
