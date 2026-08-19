class Dashboard::AutonomousRunsController < ApplicationController
  before_action :authenticate_admin_or_client!
  before_action :require_ai_autonomous!, unless: :acting_as_admin?
  before_action :set_run, only: [:show, :approve_child_titles, :destroy_child, :retry, :destroy]
  before_action :ensure_own_run!, only: [:show, :approve_child_titles, :destroy_child, :retry, :destroy]
  before_action :assign_genre_options, only: [:new, :create]
  layout "admin"

  def index
    AutonomousContentRun.recover_stale_runs! if should_recover_stale_runs?
    @runs = scoped_runs.recent.includes(:client, :pillar_column).limit(50)
    pillar_ids = @runs.map(&:pillar_column_id).compact
    @child_total_by_pillar = pillar_ids.any? ? Column.where(parent_id: pillar_ids).group(:parent_id).count : {}
    @child_completed_by_pillar =
      if pillar_ids.any?
        Column.where(parent_id: pillar_ids)
              .merge(Column.with_generated_body)
              .where(generation_status: "completed")
              .group(:parent_id)
              .count
      else
        {}
      end
    @settings = current_client.autonomous_settings_with_defaults if client_signed_in?
  end

  def new
    @run = AutonomousContentRun.new(
      cluster_limit: current_client&.default_cluster_limit || AutonomousContentRun::DEFAULT_CLUSTER_LIMIT,
      language: I18n.locale.to_s == "en" ? "en" : "ja"
    )
  end

  def create
    unless client_signed_in? || acting_as_admin?
      redirect_to dashboard_autonomous_runs_path, alert: t("drafity.dashboard.flashes.login_please")
      return
    end

    owner_client = client_signed_in? ? current_client : nil

    unless genre_allowed_for_run?(owner_client, run_params[:genre])
      redirect_to new_dashboard_autonomous_run_path, alert: t("drafity.dashboard.flashes.genre_access_denied")
      return
    end

    if owner_client && !owner_client.can_create_pillar?
      redirect_to new_dashboard_autonomous_run_path, alert: owner_client.plan_limit_message(:pillar)
      return
    end

    @run = AutonomousContentRun.start!(
      client: owner_client,
      title: run_params[:title],
      genre: GenreRegistry.resolve_key(run_params[:genre], client: owner_client).presence || run_params[:genre],
      cluster_limit: run_params[:cluster_limit],
      language: run_params[:language]
    )

    redirect_to dashboard_autonomous_runs_path, notice: t("drafity.dashboard.flashes.autonomous_started")
  rescue ActiveRecord::RecordInvalid => e
    @run = AutonomousContentRun.new(run_params)
    flash.now[:alert] = e.record.errors.full_messages.join(", ")
    render :new, status: :unprocessable_entity
  end

  def show
    @child_columns = @run.child_columns.with_list_attributes
  end

  def approve_child_titles
    if @run.approve_child_titles!
      redirect_to dashboard_autonomous_run_path(@run), notice: t("drafity.dashboard.flashes.child_body_started")
    else
      redirect_to dashboard_autonomous_run_path(@run), alert: @run.error_message.presence || t("drafity.dashboard.flashes.approve_failed")
    end
  end

  def retry
    if @run.retry!
      redirect_to dashboard_autonomous_run_path(@run), notice: t("drafity.dashboard.flashes.resumed")
    else
      redirect_to dashboard_autonomous_run_path(@run), alert: t("drafity.dashboard.flashes.resume_unavailable")
    end
  end

  def destroy_child
    child = @run.child_columns.find_by(id: params[:child_id])
    unless child
      redirect_to dashboard_autonomous_run_path(@run), alert: t("drafity.dashboard.flashes.child_not_found")
      return
    end

    if @run.status != "awaiting_child_title_approval"
      redirect_to dashboard_autonomous_run_path(@run), alert: t("drafity.dashboard.flashes.delete_only_awaiting")
      return
    end

    child.destroy
    redirect_to dashboard_autonomous_run_path(@run), notice: t("drafity.dashboard.flashes.child_title_deleted")
  end

  def destroy
    ActiveRecord::Base.transaction do
      pillar = @run.pillar_column
      @run.update!(pillar_column_id: nil)
      if pillar
        pillar.children.destroy_all
        pillar.destroy
      end
      @run.destroy!
    end

    redirect_to dashboard_autonomous_runs_path, notice: t("drafity.dashboard.flashes.cycle_deleted")
  end

  def update_settings
    unless client_signed_in?
      redirect_to dashboard_autonomous_runs_path, alert: t("drafity.dashboard.flashes.settings_client_only")
      return
    end

    notify_on = []
    notify_on << "cycle_complete" if params[:notify_cycle_complete] == "1"
    notify_on << "child_titles_ready" if params[:notify_child_titles_ready] == "1"
    notify_on = ["cycle_complete"] if notify_on.empty?

    current_client.update_autonomous_settings!(
      notify_on: notify_on,
      pause_for_child_titles: params[:pause_for_child_titles] == "1",
      default_cluster_limit: params[:default_cluster_limit]
    )

    redirect_to dashboard_autonomous_runs_path, notice: t("drafity.dashboard.flashes.settings_saved")
  end

  private

  def should_recover_stale_runs?
    ran = false
    Rails.cache.fetch("autonomous_recover_stale:#{current_actor_cache_key}", expires_in: 5.minutes) do
      ran = true
      true
    end
    ran
  end

  def current_actor_cache_key
    if acting_as_admin?
      "admin:#{current_admin.id}"
    elsif client_signed_in?
      "client:#{current_client.id}"
    else
      "anon"
    end
  end

  def require_ai_autonomous!
    return if acting_as_admin?
    return if client_signed_in? && current_client.ai_autonomous_enabled?

    redirect_to dashboard_root_path, alert: current_client&.plan_limit_message(:ai_autonomous) || t("drafity.dashboard.flashes.autonomous_plan_required")
  end

  def scoped_runs
    if acting_as_admin?
      AutonomousContentRun.includes(:client).all
    else
      current_client.autonomous_content_runs
    end
  end

  def set_run
    @run = scoped_runs.find(params[:id])
  end

  def ensure_own_run!
    return if acting_as_admin?
    return if @run.client_id == current_client.id

    redirect_to dashboard_autonomous_runs_path, alert: t("drafity.dashboard.flashes.access_denied")
  end

  def assign_genre_options
    @genre_options = dashboard_genre_registry_options
  end

  def genre_allowed_for_run?(client, genre)
    return false if genre.blank?
    return true if acting_as_admin?

    equivalent = GenreRegistry.equivalent_keys(genre)
    equivalent.any? { |k| client.genre_keys.include?(k) }
  end

  def run_params
    params.require(:autonomous_content_run).permit(:title, :genre, :cluster_limit, :language)
  end
end
