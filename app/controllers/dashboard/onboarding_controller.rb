# frozen_string_literal: true

class Dashboard::OnboardingController < ApplicationController
  layout "onboarding"

  before_action :authenticate_admin_or_client!
  before_action :reject_admin_from_first_run!
  before_action :require_first_run_client!
  before_action :assign_first_run_step

  def show
    return if redirect_started_generation_to_dashboard!

    @service_genre = current_client.first_service_genre
    @pillar = current_client.first_run_pillar
    @company_name = current_client.company.to_s
  end

  def create_service
    company = params.dig(:onboarding, :company).to_s.strip
    service_name = params.dig(:onboarding, :service_name).to_s.strip
    strong_points = params.dig(:onboarding, :strong_points).to_s.strip.presence

    if company.blank? || service_name.blank?
      @service_genre = current_client.first_service_genre
      @pillar = current_client.first_run_pillar
      @company_name = company
      @service_name = service_name
      @strong_points = strong_points
      @step = :service
      flash.now[:alert] = t("drafity.dashboard.onboarding.service_required")
      return render :show, status: :unprocessable_entity
    end

    genre = current_client.first_service_genre || current_client.service_genres.new
    english = I18n.locale.to_s.start_with?("en")
    attrs = {
      ja: english ? (genre.ja.presence || service_name) : service_name,
      service_name: service_name,
      strong_points: strong_points,
      hosts: onboarding_hosts,
      sub_categories: {},
      column_cta: {},
      key: genre.key.presence || ServiceGenre.unique_key_for(name: service_name, client: current_client, except_id: genre.id, host: request.host)
    }
    attrs[:en] = service_name if ServiceGenre.column_names.include?("en")

    genre.assign_attributes(attrs)
    unless genre.save
      @service_genre = genre
      @pillar = current_client.first_run_pillar
      @company_name = company
      @service_name = service_name
      @strong_points = strong_points
      @step = :service
      flash.now[:alert] = genre.errors.full_messages.to_sentence.presence || t("drafity.dashboard.onboarding.service_failed")
      return render :show, status: :unprocessable_entity
    end

    current_client.update_company_name(company)
    redirect_to dashboard_start_path, notice: t("drafity.dashboard.onboarding.service_saved")
  end

  def suggest_titles
    genre = current_client.first_service_genre
    if genre.blank?
      return render json: { success: false, error: t("drafity.dashboard.onboarding.need_service") }, status: :unprocessable_entity
    end

    if !current_client.can_suggest_titles?
      return render json: { success: false, error: current_client.plan_limit_message(:title_suggestion) }, status: :unprocessable_entity
    end

    keyword1 = onboarding_param(:keyword1)
    keyword2 = onboarding_param(:keyword2)
    language = onboarding_param(:language).presence || I18n.locale.to_s

    result = PillarTitleSuggestionService.call(
      keyword1: keyword1,
      keyword2: keyword2,
      target_layer: "middle",
      genre: genre.key,
      suggestion_count: 1,
      max_suggestion_count: 1,
      client: current_client,
      language: language
    )

    if result[:success]
      current_client.record_title_suggestion!
      render json: { success: true, titles: result[:titles] }
    else
      render json: { success: false, error: result[:error] }, status: :unprocessable_entity
    end
  end

  def create_title
    genre = current_client.first_service_genre
    title = params.dig(:onboarding, :title).to_s.strip
    language = Column.normalize_language(params.dig(:onboarding, :language).presence || I18n.locale.to_s)

    if genre.blank?
      return redirect_to dashboard_start_path, alert: t("drafity.dashboard.onboarding.need_service")
    end
    if title.blank?
      @service_genre = genre
      @pillar = current_client.first_run_pillar
      @company_name = current_client.company.to_s
      @step = :title
      flash.now[:alert] = t("drafity.dashboard.onboarding.title_required")
      return render :show, status: :unprocessable_entity
    end

    pillar = current_client.columns.pillars.merge(Column.without_generated_body).order(:id).first
    if pillar
      pillar.assign_attributes(title: title, genre: genre.key, language: language, article_type: "pillar")
      assign_column_client!(pillar)
      unless pillar.save
        @service_genre = genre
        @pillar = pillar
        @step = :title
        flash.now[:alert] = pillar.errors.full_messages.to_sentence
        return render :show, status: :unprocessable_entity
      end
    else
      unless current_client.can_create_pillar?
        return redirect_to dashboard_start_path, alert: current_client.plan_limit_message(:pillar)
      end

      pillar = Column.new(
        title: title,
        article_type: "pillar",
        genre: genre.key,
        status: "draft",
        language: language
      )
      assign_column_client!(pillar)
      unless pillar.save
        @service_genre = genre
        @pillar = pillar
        @step = :title
        flash.now[:alert] = pillar.errors.full_messages.to_sentence
        return render :show, status: :unprocessable_entity
      end
    end

    redirect_to dashboard_start_path, notice: t("drafity.dashboard.onboarding.title_saved")
  end

  def generate
    pillar = current_client.first_run_pillar
    if pillar.blank?
      return redirect_to dashboard_start_path, alert: t("drafity.dashboard.onboarding.need_title")
    end
    if pillar.generated_body?
      return redirect_to dashboard_root_path, notice: t("drafity.dashboard.onboarding.generate_done")
    end
    if %w[queued generating completed].include?(pillar.generation_status.to_s)
      return redirect_to dashboard_root_path, notice: t("drafity.dashboard.onboarding.generate_started")
    end

    mode = onboarding_generation_mode
    unless mode
      @service_genre = current_client.first_service_genre
      @pillar = pillar
      @company_name = current_client.company.to_s
      @step = :generate
      flash.now[:alert] = t("drafity.dashboard.onboarding.mode_required")
      return render :show, status: :unprocessable_entity
    end

    pillar.update_columns(
      generation_mode: mode,
      status: "approved",
      generation_status: "queued",
      updated_at: Time.current
    )
    GenerateColumnBodyJob.clear_cancellation!(pillar.id)

    if Rails.env.test?
      GenerateColumnBodyJob.perform_now(pillar.id)
    else
      spawn_first_run_generation!(pillar.id)
    end

    redirect_to dashboard_root_path, notice: t("drafity.dashboard.onboarding.generate_started")
  end

  private

  def redirect_started_generation_to_dashboard!
    pillar = current_client.first_run_pillar
    return false if pillar.blank?
    return false unless pillar.generated_body? || %w[queued generating completed failed cancelled].include?(pillar.generation_status.to_s)

    redirect_to dashboard_root_path
    true
  end

  def reject_admin_from_first_run!
    return unless acting_as_admin?

    redirect_to dashboard_root_path
  end

  def require_first_run_client!
    return if client_signed_in? && current_client.first_run?

    redirect_to dashboard_root_path
  end

  def assign_first_run_step
    @step = current_client.first_run_step
  end

  def onboarding_generation_mode
    mode = params.dig(:onboarding, :generation_mode).to_s
    Column::PUBLIC_GENERATION_MODES.include?(mode) ? mode : nil
  end

  def onboarding_param(key)
    params[key].presence || params.dig(:onboarding, key)
  end

  def onboarding_hosts
    hosts = [normalize_onboarding_host(request.host)]
    hosts << normalize_onboarding_host(current_client.domain) if current_client.domain.present?
    hosts.compact.uniq.reject(&:blank?)
  end

  def normalize_onboarding_host(host)
    host.to_s.downcase.sub(/\Awww\./, "").sub(/:\d+\z/, "")
  end

  def spawn_first_run_generation!(column_id)
    Thread.new do
      Rails.application.executor.wrap do
        ActiveRecord::Base.connection_pool.with_connection do
          GenerateColumnBodyJob.perform_now(column_id)
        rescue StandardError => e
          Rails.logger.error("[OnboardingGenerate] column_id=#{column_id} #{e.class}: #{e.message}")
        end
      end
    end
  end
end
