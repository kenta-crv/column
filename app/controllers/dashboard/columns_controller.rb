class Dashboard::ColumnsController < ApplicationController
  helper ColumnsHelper

  PER_PAGE_OPTIONS = [30, 50, 100].freeze
  IMAGE_GENERATION_PER_PAGE_OPTIONS = [30, 50, 100].freeze

  before_action :authenticate_admin_or_client!
  before_action :require_admin!, only: [:management]
  before_action :enforce_client_genre_param!, only: [:index, :export]
  before_action :assign_dashboard_genre_options, only: [:index, :image_generation]

  # レイアウトは既存の "admin" をそのまま流用
  layout "admin"

  @@bulk_image_generating = false

  def index
    base_scope = dashboard_columns_base_scope
    assign_dashboard_tab_counts(base_scope)

    # KPI・サイドバーバッジはタブ集計を流用（同一条件のCOUNTを繰り返さない）
    @kpi_published_count = @tab_count_published
    @kpi_draft_count = @tab_count_draft
    @kpi_pending_review_count = @tab_count_pending_review
    @pending_review_columns_count = @tab_count_pending_review
    @missing_image_columns_count = @tab_count_no_image

    filtered_base = base_scope
    if params[:genre].present?
      filtered_base = filtered_base.where(genre: GenreRegistry.equivalent_keys(params[:genre]))
    end
    if params[:language].present?
      filtered_base = filtered_base.where(language: Column.normalize_language(params[:language]))
    end

    assign_dashboard_summary_metrics(base_scope, filtered_base)

    @total_count = params[:genre].present? ? (@filtered_total_count || filtered_base.count) : @tab_count_all

    # 生成日時（created_at）表示と並びを一致させる
    scope = filtered_base.order(created_at: :desc)
    if params[:scope].present?
      case params[:scope]
      when "draft"
        scope = scope.merge(Column.without_generated_body)
      when "pillar"
        scope = scope.where(article_type: "pillar")
      when "cluster"
        scope = scope.where(article_type: %w[cluster child])
      when "pending_review"
        scope = scope.merge(Column.pending_review)
      when "published"
        scope = scope.merge(Column.published)
      when "error"
        scope = scope.where(status: "error")
      when "no_image"
        scope = scope.merge(Column.pending_review_missing_image)
      end
    end

    @per_page = PER_PAGE_OPTIONS.include?(params[:per].to_i) ? params[:per].to_i : 30
    # body 全文を読み込まない（一覧表示が明らかに重くなる主因）
    @columns = scope.with_list_attributes.page(params[:page]).per(@per_page)

    pillar_ids = @columns.select(&:pillar?).map(&:id)
    @child_counts = if pillar_ids.any?
                      dashboard_columns_base_scope.where(parent_id: pillar_ids).group(:parent_id).count
                    else
                      {}
                    end

    generation_counts = filtered_base
                          .where(generation_status: %w[queued generating])
                          .group(:generation_status)
                          .count
    @queued_count = generation_counts["queued"].to_i
    @generating_count = generation_counts["generating"].to_i
    @generating_columns = filtered_base
                            .with_list_attributes
                            .where(generation_status: %w[queued generating])
                            .order(Arel.sql("CASE generation_status WHEN 'generating' THEN 0 ELSE 1 END"), updated_at: :desc)
                            .limit(30)

    @title_suggestion_config = title_suggestion_ui_config
  end

  def generation_status
    base_scope = dashboard_columns_base_scope
    columns = base_scope
                .select(:id, :title, :generation_status, :updated_at)
                .where(generation_status: %w[queued generating])
                .order(Arel.sql("CASE generation_status WHEN 'generating' THEN 0 ELSE 1 END"), updated_at: :desc)
                .limit(30)

    generation_counts = base_scope
                          .where(generation_status: %w[queued generating])
                          .group(:generation_status)
                          .count

    recently_completed = base_scope
                           .where(generation_status: "completed")
                           .where("updated_at > ?", 5.minutes.ago)
                           .order(updated_at: :desc)
                           .limit(30)
                           .map { |c|
                             {
                               column_id: c.id,
                               status: "completed",
                               title: c.title,
                               generated_body: c.generated_body?,
                               published: c.published?,
                               path: "/columns/#{c.code.presence || c.id}",
                               file_url: c[:file].present? ? c.file.to_s : nil
                             }
                           }

    render json: {
      queued_count: generation_counts["queued"].to_i,
      generating_count: generation_counts["generating"].to_i,
      columns: columns.map { |c| { id: c.id, title: c.title, status: c.generation_status } },
      recently_completed: recently_completed
    }
  end

  # サイドバーバッジ用。レイアウト同期COUNTを避け、描画後に取得する
  def sidebar_badges
    counts = Rails.cache.fetch(sidebar_column_count_cache_key("badges_v2"), expires_in: 2.minutes) do
      compute_sidebar_badge_counts
    end

    render json: counts
  end
  
  
  def image_generation
    base_scope = dashboard_columns_base_scope

    scope = image_generation_target_scope(base_scope).order(updated_at: :desc)
    @missing_image_total = scope.count
    @per_page = IMAGE_GENERATION_PER_PAGE_OPTIONS.include?(params[:per].to_i) ? params[:per].to_i : 30
    @columns = scope.with_list_attributes.page(params[:page]).per(@per_page)
  end

  def bulk_generate_images
    if @@bulk_image_generating
      return redirect_to image_generation_dashboard_columns_path, alert: t("drafity.dashboard.flashes.image_busy")
    end

    base_scope = dashboard_columns_base_scope
    run_all = ActiveModel::Type::Boolean.new.cast(params[:run_all])

    if run_all
      target_scope = image_generation_target_scope(base_scope)
      Column.reconcile_broken_image_file_refs!(target_scope)
      target_ids = target_scope.order(updated_at: :desc).pluck(:id)
    else
      column_ids = Array(params[:column_ids]).map(&:to_i).uniq
      if column_ids.blank?
        return redirect_to image_generation_dashboard_columns_path, alert: t("drafity.dashboard.flashes.image_select_required")
      end

      Column.reconcile_broken_image_file_refs!(base_scope.where(id: column_ids))

      target_ids = image_generation_target_scope(base_scope).where(id: column_ids).pluck(:id)
      if target_ids.size < column_ids.size
        return redirect_to image_generation_dashboard_columns_path, alert: t("drafity.dashboard.flashes.image_invalid_selection")
      end
    end

    if target_ids.blank?
      return redirect_to image_generation_dashboard_columns_path, alert: t("drafity.dashboard.flashes.image_none_found")
    end

    if client_signed_in?
      remaining = current_client.plan_limits[:image_generations] - current_client.image_generation_usage_count
      if remaining <= 0
        return redirect_to image_generation_dashboard_columns_path,
                           alert: current_client.plan_limit_message(:image_generation)
      end
      target_ids = target_ids.first(remaining)
    end

    if target_ids.any?
      @@bulk_image_generating = true

      Thread.new do
        Rails.application.executor.wrap do
          begin
            ActiveRecord::Base.connection_pool.with_connection do
              Column.where(id: target_ids).merge(Column.without_image_file).find_each do |column|
                begin
                  FluxImageGeneratorService.generate!(column)
                rescue => e
                  Rails.logger.error "[Thread Image Gen Error] ID: #{column.id} - #{e.message}"
                end
              end
            end
          ensure
            @@bulk_image_generating = false
          end
        end
      end

      redirect_to dashboard_root_path, notice: t("drafity.dashboard.flashes.image_started", count: target_ids.size)
    else
      redirect_to image_generation_dashboard_columns_path, alert: t("drafity.dashboard.flashes.image_none_found")
    end
  end

  def check_bulk_image_count
    base_scope = dashboard_columns_base_scope

    query = image_generation_target_scope(base_scope)
    if params[:bulk_genre].present? && admin_or_allowed_genre?(params[:bulk_genre])
      query = query.where(genre: GenreRegistry.equivalent_keys(params[:bulk_genre]))
    end
    query = query.merge(Column.with_article_type_filter(params[:bulk_article_type])) if params[:bulk_article_type].present?

    render json: {
      count: query.count,
      is_running: @@bulk_image_generating
    }
  end

  def export
    # Ruby標準のCSVライブラリを確実にロード
    require "csv"

    # 1. 画面の絞り込みと完全に同じクエリ条件のベースを構築
    scope = dashboard_columns_base_scope.order(updated_at: :desc)

    if params[:scope].present?
      case params[:scope]
      when "draft"
        scope = scope.merge(Column.without_generated_body)
      when "pillar"
        scope = scope.where(article_type: "pillar")
      when "cluster"
        scope = scope.where(article_type: %w[cluster child])
      when "pending_review"
        scope = scope.merge(Column.pending_review)
      when "published"
        scope = scope.merge(Column.published)
      when "error"
        scope = scope.where(status: "error")
      when "no_image"
        scope = scope.merge(Column.pending_review_missing_image)
      end
    end

    if params[:genre].present?
      scope = scope.where(genre: GenreRegistry.equivalent_keys(params[:genre]))
    end

    if params[:language].present?
      scope = scope.where(language: params[:language])
    end

    # 2. CSVエクスポート用のストリーム・ヘッダー準備
    filename = "columns_export_#{Time.current.strftime('%Y%m%d%H%M%S')}.csv"
    keep_html = params[:export_format] == "html"
    sanitizer = ActionView::Base.full_sanitizer

    headers.delete("Content-Length")
    headers["Content-Type"] = "text/csv; charset=utf-8"
    headers["Content-Disposition"] = "attachment; filename=\"#{filename}\""
    headers["Cache-Control"] = "no-cache"

    # 3. 大容量データストリーミング
    self.response_body = Enumerator.new do |yielder|
      yielder << "\xEF\xBB\xBF"
      yielder << ::CSV.generate_line([t("drafity.dashboard.csv.headers.id"), t("drafity.dashboard.csv.headers.title"), t("drafity.dashboard.csv.headers.genre"), t("drafity.dashboard.csv.headers.article_type"), t("drafity.dashboard.csv.headers.status"), t("drafity.dashboard.csv.headers.body"), t("drafity.dashboard.csv.headers.updated_at")])

      scope.find_in_batches(batch_size: 1000) do |batch|
        batch.each do |c|
          body_content = c.body.to_s
          unless keep_html
            body_content = sanitizer.sanitize(body_content)
          end

          yielder << ::CSV.generate_line([
            c.id,
            c.title,
            c.genre,
            c.article_type,
            c.status,
            body_content,
            c.updated_at.strftime("%Y/%m/%d %H:%M")
          ])
        end
      end
    end
  end

  def remove_image
    column = dashboard_columns_base_scope.find(params[:id])
    column.update(file: nil)

    redirect_to dashboard_columns_path
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_columns_path, alert: t("drafity.dashboard.flashes.column_access_denied")
  end

  def stop_generation
    column = dashboard_columns_base_scope.find(params[:id])
    Rails.logger.info("[StopGeneration] request received column_id=#{column.id} status=#{column.generation_status}")

    unless %w[generating queued].include?(column.generation_status)
      return redirect_to dashboard_columns_path, alert: t("drafity.dashboard.flashes.stop_only_generating")
    end

    GenerateColumnBodyJob.request_stop!(column.id)
    column.update!(generation_status: "cancelled")
    redirect_to dashboard_columns_path, notice: t("drafity.dashboard.flashes.generation_stopped")
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_columns_path, alert: t("drafity.dashboard.flashes.column_access_denied")
  end

  def setting; end

  def management
    @clients = Client.includes(:subscriptions).order(created_at: :desc)
  end

  def suggest_titles
    unless admin_or_allowed_genre?(params[:genre])
      return render json: { success: false, error: t("drafity.dashboard.flashes.genre_access_denied") }
    end

    if client_signed_in? && !current_client.can_suggest_titles?
      return render json: { success: false, error: current_client.plan_limit_message(:title_suggestion) }
    end

    max_per_use = if client_signed_in?
                    current_client.max_title_suggestion_count
                  else
                    Subscription::TITLE_SUGGESTION_ADMIN_BAR_MAX
                  end

    client = client_signed_in? ? current_client : nil
    sub_genre = sanitize_sub_genre_param(params[:genre], params[:sub_genre], client: client)

    result = PillarTitleSuggestionService.call(
      keyword1: params[:keyword1],
      keyword2: params[:keyword2],
      target_layer: params[:target_layer],
      genre: params[:genre],
      sub_genre: sub_genre,
      custom_prompt: params[:custom_prompt],
      suggestion_count: params[:suggestion_count],
      max_suggestion_count: max_per_use,
      client: client,
      language: params[:language]
    )

    if result[:success]
      current_client.record_title_suggestion! if client_signed_in?
      render json: { success: true, titles: result[:titles] }
    else
      render json: { success: false, error: result[:error] }
    end
  end

  def create_from_suggestion
    if client_signed_in? && !current_client.can_create_pillar?
      return render json: { success: false, error: current_client.plan_limit_message(:pillar) }
    end

    client = client_signed_in? ? current_client : nil
    @column = Column.new(
      title: params[:title],
      article_type: "pillar",
      genre: params[:genre],
      sub_genre: sanitize_sub_genre_param(params[:genre], params[:sub_genre], client: client),
      status: "draft",
      language: Column.normalize_language(params[:language])
    )
    assign_column_client!(@column)

    if @column.save
      render json: { success: true, column_id: @column.id, redirect_path: edit_column_path(@column) }
    else
      render json: { success: false, error: @column.errors.full_messages.join(", ") }
    end
  end

  def bulk_create_from_suggestions
    titles = params[:titles]
    genre = params[:genre]
    client = client_signed_in? ? current_client : nil
    sub_genre = sanitize_sub_genre_param(genre, params[:sub_genre], client: client)

    if titles.blank? || genre.blank?
      render json: { success: false, error: t("drafity.dashboard.flashes.title_genre_required") }
      return
    end

    unless admin_or_allowed_genre?(genre)
      render json: { success: false, error: t("drafity.dashboard.flashes.genre_access_denied") }
      return
    end

    created_count = 0
    errors = []
    remaining_slots = if client_signed_in?
                        [current_client.plan_limits[:pillar_articles] - current_client.pillar_slots_used, 0].max
                      else
                        titles.size
                      end

    titles.first(remaining_slots).each do |title|
      column = Column.new(
        title: title,
        article_type: "pillar",
        genre: genre,
        sub_genre: sub_genre,
        status: "draft",
        language: Column.normalize_language(params[:language])
      )
      assign_column_client!(column)

      if column.save
        created_count += 1
      else
        errors << "#{title}: #{column.errors.full_messages.join(', ')}"
      end
    end

    if created_count > 0
      render json: { success: true, created_count: created_count, errors: errors }
    elsif remaining_slots <= 0 && client_signed_in?
      render json: { success: false, error: current_client.plan_limit_message(:pillar) }
    else
      render json: { success: false, error: t("drafity.dashboard.flashes.column_create_failed", errors: errors.join(", ")) }
    end
  end

  private

  def title_suggestion_ui_config
    if client_signed_in?
      plan_max = current_client.max_title_suggestion_count
      bar_max = Subscription::TITLE_SUGGESTION_BAR_MAX
      {
        default: 1,
        max: plan_max,
        bar_max: bar_max,
        remaining: [current_client.plan_limits[:title_suggestions] - current_client.title_suggestion_usage_count, 0].max,
        monthly_limit: current_client.plan_limits[:title_suggestions]
      }
    else
      bar_max = Subscription::TITLE_SUGGESTION_ADMIN_BAR_MAX
      {
        default: 1,
        max: bar_max,
        bar_max: bar_max,
        remaining: nil
      }
    end
  end

  def enforce_client_genre_param!
    return unless client_signed_in?
    return if params[:genre].blank?
    return if admin_or_allowed_genre?(params[:genre])

    redirect_to dashboard_columns_path(scope: params[:scope]), alert: t("drafity.dashboard.flashes.genre_access_denied")
  end

  def assign_dashboard_genre_options
    @dashboard_genre_options = dashboard_genre_registry_options
    @dashboard_sub_categories_json = dashboard_sub_categories_json
    @sub_category_config = sub_category_ui_config
    @needs_genre_setup = client_signed_in? && !acting_as_admin? && @dashboard_genre_options.blank?
  end

  def sanitize_sub_genre_param(genre, sub_genre, client: nil)
    return nil if genre.blank? || sub_genre.blank?

    genre_key = GenreRegistry.resolve_key(genre, client: client) || genre
    subs = GenreRegistry.genres(client: client).dig(genre_key.to_sym, :sub_categories) || {}
    return nil unless subs.key?(sub_genre.to_sym) || subs.key?(sub_genre.to_s)

    sub_genre.to_s
  end

  def image_generation_target_scope(base_scope)
    base_scope.merge(Column.pending_review_missing_image)
  end

  def assign_dashboard_tab_counts(scope)
    cache_key = sidebar_column_count_cache_key("dashboard_tabs_v3")
    counts = Rails.cache.fetch(cache_key, expires_in: 90.seconds) do
      compute_dashboard_tab_counts(scope)
    end

    @tab_count_all,
    @tab_count_draft,
    @tab_count_pillar,
    @tab_count_cluster,
    @tab_count_pending_review,
    @tab_count_published,
    @tab_count_error,
    @tab_count_no_image = Array(counts).map { |v| v.to_i }
  end

  def compute_dashboard_tab_counts(scope)
    scope = scope.unscope(:order)

    if ActiveRecord::Base.connection.adapter_name.match?(/postgre/i)
      # body 全文の TRIM/比較を避け、octet_length で有無だけ見る（TOAST 展開を抑える）
      scope.pick(
        Arel.sql("COUNT(*)"),
        Arel.sql("COUNT(*) FILTER (WHERE body IS NULL OR octet_length(body) = 0)"),
        Arel.sql("COUNT(*) FILTER (WHERE article_type = 'pillar')"),
        Arel.sql("COUNT(*) FILTER (WHERE article_type IN ('cluster', 'child'))"),
        Arel.sql("COUNT(*) FILTER (WHERE body IS NOT NULL AND octet_length(body) > 0 AND published_at IS NULL)"),
        Arel.sql("COUNT(*) FILTER (WHERE published_at IS NOT NULL)"),
        Arel.sql("COUNT(*) FILTER (WHERE status = 'error')"),
        Arel.sql("COUNT(*) FILTER (WHERE body IS NOT NULL AND octet_length(body) > 0 AND published_at IS NULL AND (file IS NULL OR file = ''))")
      ) || Array.new(8, 0)
    else
      [
        scope.count,
        scope.merge(Column.without_generated_body).count,
        scope.where(article_type: "pillar").count,
        scope.where(article_type: %w[cluster child]).count,
        scope.merge(Column.pending_review).count,
        scope.merge(Column.published).count,
        scope.where(status: "error").count,
        scope.merge(Column.pending_review_missing_image).count
      ]
    end
  end

  def assign_dashboard_summary_metrics(base_scope, filtered_base)
    genre_key = params[:genre].to_s
    cache_key = sidebar_column_count_cache_key("dashboard_summary_v1:#{genre_key}")

    summary = Rails.cache.fetch(cache_key, expires_in: 90.seconds) do
      {
        avg_quality: base_scope.where.not(quality_score: nil).where("quality_score > 0").average(:quality_score)&.round(1),
        filtered_total: genre_key.present? ? filtered_base.count : nil,
        genre_pillar: merge_canonical_genre_counts(
          filtered_base.where(article_type: "pillar").group(:genre).count
        ),
        genre_child: merge_canonical_genre_counts(
          filtered_base.where(article_type: %w[cluster child]).group(:genre).count
        )
      }
    end

    @kpi_avg_quality_score = summary[:avg_quality]
    @filtered_total_count = summary[:filtered_total]
    @genre_pillar_counts = summary[:genre_pillar]
    @genre_child_counts = summary[:genre_child]
  end

  def broadcast_generation_status(column)
    GenerationChannelBroadcaster.broadcast(column)
  end

  def compute_sidebar_badge_counts
    scope = dashboard_columns_base_scope.unscope(:order)

    if ActiveRecord::Base.connection.adapter_name.match?(/postgre/i)
      pending_review, missing_image = scope.pick(
        Arel.sql("COUNT(*) FILTER (WHERE body IS NOT NULL AND octet_length(body) > 0 AND published_at IS NULL)"),
        Arel.sql("COUNT(*) FILTER (WHERE body IS NOT NULL AND octet_length(body) > 0 AND published_at IS NULL AND (file IS NULL OR file = ''))")
      ) || [0, 0]

      {
        pending_review: pending_review.to_i,
        missing_image: missing_image.to_i
      }
    else
      {
        pending_review: scope.merge(Column.pending_review).count,
        missing_image: scope.merge(Column.pending_review_missing_image).count
      }
    end
  end
end
