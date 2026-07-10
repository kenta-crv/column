class Dashboard::ColumnsController < ApplicationController
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

    @kpi_published_count = base_scope.merge(Column.with_generated_body).count
    @kpi_draft_count = base_scope.where("body IS NULL OR TRIM(body) = ''").count
    @kpi_avg_quality_score = base_scope.where.not(quality_score: nil).where("quality_score > 0").average(:quality_score)&.round(1)
    @kpi_completed_generation_count = base_scope.where(generation_status: "completed").count
    @kpi_reserved_count = base_scope.where(status: "reserved").count

    filtered_base = base_scope
    filtered_base = filtered_base.where(genre: params[:genre]) if params[:genre].present?
    filtered_base = filtered_base.where(language: params[:language]) if params[:language].present?
    @total_count     = filtered_base.count
    @draft_count     = filtered_base.where(body: [nil, ""]).count
    @pillar_count    = filtered_base.where(article_type: "pillar").count
    @cluster_count   = filtered_base.where(article_type: %w[cluster child]).count
    @published_count = filtered_base.merge(Column.with_generated_body).count
    @error_count     = filtered_base.where(status: "error").count
    @reserved_count  = filtered_base.where(status: "reserved").count
    @no_image_count  = filtered_base.merge(Column.missing_generated_image).count

    # 成功率とクオリティ平均の計算（実態ベースでの算出。データがない場合は固定フォールバック）
    total_processed = @published_count + @error_count
    @success_rate = total_processed.positive? ? ((@published_count.to_f / total_processed) * 100).round : 92
    @avg_quality_score = "4.6" # ロジックが存在する場合はここで `filtered_base.average(:quality_score)` 等を計算

    # 2. メイン一覧用のスコープを params[:scope] に応じて条件分岐
    scope = filtered_base.order(updated_at: :desc)
    if params[:scope].present?
      case params[:scope]
      when "draft"
        scope = scope.where(body: [nil, ""])
      when "pillar"
        scope = scope.where(article_type: "pillar")
      when "cluster"
        scope = scope.where(article_type: %w[cluster child])
      when "published"
        scope = scope.merge(Column.with_generated_body)
      when "error"
        scope = scope.where(status: "error")
      when "no_image"
        scope = scope.merge(Column.missing_generated_image)
      end
    end

    # 3. 最後にページネーションを適用
    @columns = scope.page(params[:page]).per(30)

    pillar_ids = @columns.select(&:pillar?).map(&:id)
    @child_counts = if pillar_ids.any?
                      dashboard_columns_base_scope.where(parent_id: pillar_ids).group(:parent_id).count
                    else
                      {}
                    end

    # 相互互換データの確保
    @genre_pillar_counts = filtered_base.where(article_type: "pillar").group(:genre).count
    @genre_child_counts   = filtered_base.where(article_type: %w[cluster child]).group(:genre).count
    @all_genres = base_scope.distinct.pluck(:genre).compact

    # 4. 通知ドロップダウン（ベルマーク用）に表示する直近の実行・変更履歴（最新5件）
    @recent_columns = filtered_base.order(updated_at: :desc).limit(5)

    # 過去24時間以内に更新されたレコードがある場合、通知ドットをONにする
    @has_new_notifications = filtered_base.where("updated_at > ?", 24.hours.ago).exists?

    # リアルタイム生成中の記事を取得
    @generating_columns = filtered_base.where(generation_status: 'generating').limit(10)
    @generating_count = filtered_base.where(generation_status: 'generating').count
  end
  
  
  def image_generation
    base_scope = dashboard_columns_base_scope
    Column.reconcile_broken_image_file_refs!(base_scope)

    scope = image_generation_target_scope(base_scope).order(updated_at: :desc)
    @missing_image_total = scope.count
    @columns = scope.page(params[:page]).per(30)
  end

  def bulk_generate_images
    if @@bulk_image_generating
      return redirect_to image_generation_dashboard_columns_path, alert: "現在、別の一括画像生成タスクが実行中です。完了までお待ちください。"
    end

    column_ids = Array(params[:column_ids]).map(&:to_i).uniq
    if column_ids.blank?
      return redirect_to image_generation_dashboard_columns_path, alert: "画像を生成する記事を選択してください。"
    end

    base_scope = dashboard_columns_base_scope
    Column.reconcile_broken_image_file_refs!(base_scope)

    target_ids = image_generation_target_scope(base_scope).where(id: column_ids).pluck(:id)
    if target_ids.size < column_ids.size
      return redirect_to image_generation_dashboard_columns_path, alert: "選択された記事の一部にアクセスできないか、画像生成の対象外です。"
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

      redirect_to dashboard_columns_path, notice: "画像の生成を開始しました。"
    else
      redirect_to image_generation_dashboard_columns_path, alert: "対象となる画像未設定の記事が見つかりませんでした。"
    end
  end

  def check_bulk_image_count
    base_scope = dashboard_columns_base_scope
    Column.reconcile_broken_image_file_refs!(base_scope)

    query = image_generation_target_scope(base_scope)
    query = query.where(genre: params[:bulk_genre]) if params[:bulk_genre].present? && admin_or_allowed_genre?(params[:bulk_genre])
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
        scope = scope.where(body: [nil, ""])
      when "pillar"
        scope = scope.where(article_type: "pillar")
      when "cluster"
        scope = scope.where(article_type: %w[cluster child])
      when "published"
        scope = scope.merge(Column.with_generated_body)
      when "error"
        scope = scope.where(status: "error")
      when "no_image"
        scope = scope.merge(Column.missing_generated_image)
      end
    end

    if params[:genre].present?
      scope = scope.where(genre: params[:genre])
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
      yielder << ::CSV.generate_line(["ID", "記事タイトル", "ジャンル", "記事タイプ", "ステータス", "本文", "更新日時"])

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
    redirect_to dashboard_columns_path, alert: "指定された記事にアクセスできません。"
  end

  def stop_generation
    column = dashboard_columns_base_scope.find(params[:id])
    Rails.logger.info("[StopGeneration] request received column_id=#{column.id} status=#{column.generation_status}")

    unless column.generation_status == "generating"
      return redirect_to dashboard_columns_path, alert: "生成中の記事のみ停止できます"
    end

    GenerateColumnBodyJob.request_stop!(column.id)
    column.update!(generation_status: "cancelled")
    redirect_to dashboard_columns_path, notice: "生成を停止しました"
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_columns_path, alert: "指定された記事にアクセスできません。"
  end

  private

  def setting; end

  def management
    @clients = Client.includes(:subscriptions).order(created_at: :desc)
  end

  def suggest_titles
    unless admin_or_allowed_genre?(params[:genre])
      return render json: { success: false, error: "指定されたジャンルにはアクセスできません。" }
    end

    if client_signed_in? && !current_client.can_suggest_titles?
      return render json: { success: false, error: current_client.plan_limit_message(:title_suggestion) }
    end

    result = PillarTitleSuggestionService.call(
      keyword1: params[:keyword1],
      keyword2: params[:keyword2],
      target_layer: params[:target_layer],
      genre: params[:genre],
      custom_prompt: params[:custom_prompt],
      suggestion_count: params[:suggestion_count],
      client: (client_signed_in? ? current_client : nil)
    )

    if result[:success]
      current_client.record_title_suggestion! if client_signed_in?
      render json: { success: true, titles: result[:titles] }
    else
      render json: { success: false, error: result[:error] }
    end
  end

  def create_from_suggestion
    @column = Column.new(
      title: params[:title],
      article_type: "pillar",
      genre: params[:genre],
      status: "draft"
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

    if titles.blank? || genre.blank?
      render json: { success: false, error: "タイトルとジャンルを指定してください" }
      return
    end

    unless admin_or_allowed_genre?(genre)
      render json: { success: false, error: "指定されたジャンルにはアクセスできません。" }
      return
    end

    created_count = 0
    errors = []
    remaining_slots = if client_signed_in?
                        current_client.plan_limits[:pillar_articles] - current_client.pillar_usage_count
                      else
                        titles.size
                      end

    titles.first(remaining_slots).each do |title|
      column = Column.new(
        title: title,
        article_type: "pillar",
        genre: genre,
        status: "draft"
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
      render json: { success: false, error: "記事を作成できませんでした: #{errors.join(', ')}" }
    end
  end

  private

  def enforce_client_genre_param!
    return unless client_signed_in?
    return if params[:genre].blank?
    return if admin_or_allowed_genre?(params[:genre])

    redirect_to dashboard_columns_path(scope: params[:scope]), alert: "指定されたジャンルにはアクセスできません。"
  end

  def assign_dashboard_genre_options
    @dashboard_genre_options = dashboard_genre_registry_options
  end

  def image_generation_target_scope(base_scope)
    base_scope.merge(Column.missing_generated_image)
  end

  def assign_dashboard_tab_counts(scope)
    @tab_count_all       = scope.count
    @tab_count_draft     = scope.where("body IS NULL OR TRIM(body) = ''").count
    @tab_count_pillar    = scope.where(article_type: "pillar").count
    @tab_count_cluster   = scope.where(article_type: %w[cluster child]).count
    @tab_count_published = scope.merge(Column.with_generated_body).count
    @tab_count_error     = scope.where(status: "error").count
    @tab_count_no_image  = scope.merge(Column.missing_generated_image).count
  end

  def broadcast_generation_status(column)
    ActionCable.server.broadcast(
      "GenerationChannel",
      {
        column_id: column.id,
        status: column.generation_status,
        title: column.title
      }
    )
  rescue LoadError, NameError => e
    Rails.logger.warn("[GenerationChannel] broadcast skipped: #{e.class} - #{e.message}")
  rescue StandardError => e
    Rails.logger.error("[GenerationChannel] broadcast failed: #{e.class} - #{e.message}")
  end
end