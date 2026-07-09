class Dashboard::AutonomousRunsController < ApplicationController
  before_action :authenticate_admin_or_client!
  before_action :require_ai_autonomous!, unless: :admin_signed_in?
  before_action :require_client_account!, only: [:new, :create, :update_settings]
  before_action :set_run, only: [:show, :approve_child_titles, :destroy_child, :retry, :destroy]
  before_action :ensure_own_run!, only: [:show, :approve_child_titles, :destroy_child, :retry, :destroy]
  before_action :assign_genre_options, only: [:new, :create]
  layout "admin"

  def index
    AutonomousContentRun.recover_stale_runs! if client_signed_in?
    @runs = scoped_runs.recent.limit(50)
    @settings = current_client.autonomous_settings_with_defaults if client_signed_in?
  end

  def new
    @run = AutonomousContentRun.new(
      cluster_limit: current_client&.default_cluster_limit || AutonomousContentRun::DEFAULT_CLUSTER_LIMIT
    )
  end

  def create
    unless client_signed_in?
      redirect_to dashboard_autonomous_runs_path, alert: "クライアントアカウントでログインしてください。"
      return
    end

    unless admin_or_allowed_genre?(run_params[:genre])
      redirect_to new_dashboard_autonomous_run_path, alert: "指定されたジャンルにはアクセスできません。"
      return
    end

    unless current_client.can_create_pillar?
      redirect_to new_dashboard_autonomous_run_path, alert: current_client.plan_limit_message(:pillar)
      return
    end

    @run = AutonomousContentRun.start!(
      client: current_client,
      title: run_params[:title],
      genre: run_params[:genre],
      cluster_limit: run_params[:cluster_limit]
    )

    redirect_to dashboard_autonomous_runs_path, notice: "AI主導生成を開始しました。Sidekiqでバックグラウンド処理されます。"
  rescue ActiveRecord::RecordInvalid => e
    @run = AutonomousContentRun.new(run_params)
    flash.now[:alert] = e.record.errors.full_messages.join(", ")
    render :new, status: :unprocessable_entity
  end

  def show
    @child_columns = @run.child_columns
  end

  def approve_child_titles
    if @run.approve_child_titles!
      redirect_to dashboard_autonomous_run_path(@run), notice: "子記事の本文生成を開始しました。"
    else
      redirect_to dashboard_autonomous_run_path(@run), alert: @run.error_message.presence || "承認できませんでした。"
    end
  end

  def retry
    if @run.retry!
      redirect_to dashboard_autonomous_run_path(@run), notice: "生成を再開しました。Sidekiqで処理されます。"
    else
      redirect_to dashboard_autonomous_run_path(@run), alert: "再開できない状態です。"
    end
  end

  def destroy_child
    child = @run.child_columns.find_by(id: params[:child_id])
    unless child
      redirect_to dashboard_autonomous_run_path(@run), alert: "子記事が見つかりません。"
      return
    end

    if @run.status != "awaiting_child_title_approval"
      redirect_to dashboard_autonomous_run_path(@run), alert: "承認待ちのときのみ削除できます。"
      return
    end

    child.destroy
    redirect_to dashboard_autonomous_run_path(@run), notice: "子タイトルを削除しました。"
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

    redirect_to dashboard_autonomous_runs_path, notice: "自律生成サイクルを削除しました。"
  end

  def update_settings
    notify_on = []
    notify_on << "cycle_complete" if params[:notify_cycle_complete] == "1"
    notify_on << "child_titles_ready" if params[:notify_child_titles_ready] == "1"
    notify_on = ["cycle_complete"] if notify_on.empty?

    current_client.update_autonomous_settings!(
      notify_on: notify_on,
      pause_for_child_titles: params[:pause_for_child_titles] == "1",
      default_cluster_limit: params[:default_cluster_limit]
    )

    redirect_to dashboard_autonomous_runs_path, notice: "設定を保存しました。"
  end

  private

  def require_ai_autonomous!
    return if admin_signed_in?
    return if client_signed_in? && current_client.ai_autonomous_enabled?

    redirect_to dashboard_root_path, alert: current_client&.plan_limit_message(:ai_autonomous) || "AI主導生成はビジネスプラン以上で利用できます。"
  end

  def require_client_account!
    return if client_signed_in?

    redirect_to dashboard_autonomous_runs_path, alert: "クライアントアカウントでログインしてください。"
  end

  def scoped_runs
    if admin_signed_in?
      AutonomousContentRun.all
    else
      current_client.autonomous_content_runs
    end
  end

  def set_run
    @run = scoped_runs.find(params[:id])
  end

  def ensure_own_run!
    return if admin_signed_in?
    return if @run.client_id == current_client.id

    redirect_to dashboard_autonomous_runs_path, alert: "アクセスできません。"
  end

  def assign_genre_options
    @genre_options = dashboard_genre_registry_options
  end

  def run_params
    params.require(:autonomous_content_run).permit(:title, :genre, :cluster_limit)
  end
end
