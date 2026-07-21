class ColumnsController < ApplicationController
  layout :resolve_columns_layout

  before_action :authenticate_admin_or_client!, except: [:index, :show]
  before_action :authenticate_admin_or_client!, only: [:bulk_update_drafts]
  before_action :redirect_legacy_columns_index!, only: [:index]
  before_action :set_column, only: [:show, :edit, :update, :destroy, :approve, :generate_title, :remove_image, :create_child_title, :publish, :unpublish]
  before_action :require_readable_column!, only: [:show]
  before_action :require_column_access!, only: [:edit, :update, :destroy, :approve, :generate_title, :remove_image, :create_child_title, :publish, :unpublish]
  before_action :set_breadcrumbs
  before_action :assign_column_form_genre_options, only: [:new, :create, :edit, :update]
  
  @@bulk_image_generating = false

  def index
    columns = columns_list_scope.select(
      :id, :title, :description, :body,
      :genre, :article_type, :updated_at,
      :file, :code, :parent_id, :status,
      :sub_genre, :client_id
    )

    if params[:q].present?
      columns = columns.where(
        "title LIKE ? OR keyword LIKE ? OR description LIKE ?",
        "%#{params[:q]}%", "%#{params[:q]}%", "%#{params[:q]}%"
      )
    end

    columns = columns.where(genre: params[:selected_genre]) if params[:selected_genre].present?
    columns = columns.order(updated_at: :desc)

    @paginated_columns = columns.page(params[:page]).per(30)
    @columns = @paginated_columns.to_a

    stats_scope = columns_manage_view? ? dashboard_columns_base_scope : columns_list_scope
    genre_key = current_public_genre_key.presence || default_public_genre_key
    genre_values = public_genre_filter_values(genre_key, client: client_signed_in? ? current_client : nil)
    stats_scope = stats_scope.where(genre: genre_values) if genre_values.present?

    if params[:article_type] == "pillar"
      @grouped_columns = @columns.group_by(&:genre)
      @all_genres = stats_scope.where(article_type: "pillar").distinct.pluck(:genre).compact
    end

    if @columns.present?
      column_ids = @columns.map(&:id)
      @child_counts = stats_scope.where(parent_id: column_ids).group(:parent_id).count
    else
      @child_counts = {}
    end

    base_count_query = stats_scope
    if params[:q].present?
      base_count_query = base_count_query.where(
        "title LIKE ? OR keyword LIKE ? OR description LIKE ?",
        "%#{params[:q]}%", "%#{params[:q]}%", "%#{params[:q]}%"
      )
    end
    base_count_query = base_count_query.where(genre: params[:selected_genre]) if params[:selected_genre].present?

    @genre_pillar_counts = base_count_query.where(article_type: "pillar").group(:genre).count
    @genre_child_counts  = base_count_query.where(article_type: %w[child cluster]).group(:genre).count

    @current_genre_key = genre_key
    @columns_manage_view = columns_manage_view?
  end

  def show
    current_genre_key = if defined?(GenreRegistry) && GenreRegistry.respond_to?(:from_ja)
                          GenreRegistry.from_ja(@column.genre)
                        end
    current_genre_key ||= @column.genre.to_s.strip.downcase

    if @column.article_type == "pillar"
      if can_manage_column?(@column)
        @children = @column.children.order(updated_at: :desc)
        @child_article_quota = child_article_quota_for(@column)
      else
        @children = @column.children.merge(Column.published).order(updated_at: :desc)
      end
    else
      @children = []
    end

    markdown_body = @column.body.presence || "## 記事はまだ生成されていません。"
    raw_html_body = Kramdown::Document.new(markdown_body).to_html
    sanitized_html_body = raw_html_body.gsub(/<span[^>]*>|<\/span>/, '').gsub(/ style=\"[^\"]*\"/, '')

    @headings = []
    @column_body_with_ids = sanitized_html_body.gsub(/<(h[2-4])>(.*?)<\/\1>/m) do
      tag, text = Regexp.last_match(1), Regexp.last_match(2)
      clean_text = text.gsub('#', '')
      idx = @headings.size
      @headings << { tag: tag, text: clean_text, id: "heading-#{idx}", level: tag[1].to_i }
      "<#{tag} id='heading-#{idx}'>#{clean_text}</#{tag}>"
    end
  end
  
  def bulk_update_drafts
    column_ids = params[:column_ids]
    if column_ids.blank?
      return redirect_to delete_bulk_fallback_path, alert: "未選択"
    end

    scope = dashboard_columns_base_scope.where(id: column_ids)
    action_type = Array(params[:action_type]).last.to_s

    case action_type
    when "approve_bulk"
      draft_scope = scope.merge(Column.without_generated_body)
      if draft_scope.none?
        return redirect_to(
          delete_bulk_fallback_path,
          alert: "本文未生成の記事が選択されていません"
        )
      end

      target_ids = draft_scope.pluck(:id)
      pending_ids = prepare_columns_for_generation!(target_ids)
      if pending_ids.blank?
        return redirect_to(delete_bulk_fallback_path, alert: "対象の記事が見つかりませんでした")
      end

      spawn_sequential_body_generation!(pending_ids)
      Rails.logger.info("[BulkGenerate] started #{pending_ids.size} columns (ids=#{pending_ids.join(',')})")
      return redirect_to(delete_bulk_fallback_path, notice: "#{pending_ids.size}件の本文生成を開始しました")

    when "publish_bulk"
      publish_scope = scope.merge(Column.pending_review)
      if publish_scope.none?
        return redirect_to(
          delete_bulk_fallback_path,
          alert: "公開可能な記事（本文あり・未公開）が選択されていません"
        )
      end

      published_count = 0
      publish_scope.find_each do |column|
        next unless column.publish!

        published_count += 1
      end

      Rails.logger.info("[BulkPublish] published #{published_count} columns")
      return redirect_to(delete_bulk_fallback_path, notice: "#{published_count}件の記事を公開しました")

    when "delete_bulk"
      deleted_count = scope.delete_all
      return redirect_to(delete_bulk_fallback_path, notice: "#{deleted_count}件を削除しました")
    else
      return redirect_to(delete_bulk_fallback_path, alert: "操作種別が不正です")
    end
  end

  # ======================
  # CRUD
  # ======================
  def new
    @column = Column.new
  end

  def create
    @column = Column.new(column_params)
    assign_column_client!(@column)

    if client_signed_in? && @column.parent_id.blank? && @column.article_type.blank?
      @column.article_type = "pillar"
    end

    unless admin_or_allowed_genre?(@column.genre)
      @column.errors.add(:genre, "は利用できません")
      render :new, status: :unprocessable_entity
      return
    end

    if @column.save
      redirect_to dashboard_root_path, notice: "作成しました"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    add_breadcrumb "記事編集", edit_column_path(@column)
  end

  def update
    unless admin_or_allowed_genre?(column_params[:genre])
      @column.errors.add(:genre, "は利用できません")
      render :edit, status: :unprocessable_entity
      return
    end

    if @column.update(column_params)
      redirect_to dashboard_root_path, notice: "更新しました"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @column.destroy
    redirect_to columns_path, notice: "削除しました"
  end

  # ======================
  # IMAGE ACTIONS (NON-SIDEKIQ THREAD BASE)
  # ======================
  
  def remove_image
    @column.update_column(:file, nil)
    redirect_back fallback_location: column_path(@column), notice: "画像を削除しました。"
  end

  def check_bulk_image_count
    genre        = params[:bulk_genre]
    article_type = params[:bulk_article_type]

    base_scope = dashboard_columns_base_scope
    Column.reconcile_broken_image_file_refs!(base_scope)

    query = base_scope.merge(Column.missing_generated_image)
    query = query.where(genre: genre) if genre.present? && admin_or_allowed_genre?(genre)
    query = query.merge(Column.with_article_type_filter(article_type)) if article_type.present?

    render json: { count: query.count, is_running: @@bulk_image_generating }
  end

  def bulk_generate_images
    if @@bulk_image_generating
      return redirect_to columns_path, alert: "現在、別の一括画像生成タスクが実行中です。完了までお待ちください。"
    end

    column_ids = Array(params[:column_ids]).map(&:to_i).uniq
    if column_ids.blank?
      return redirect_to columns_path, alert: "画像を生成する記事を選択してください。"
    end

    base_scope = dashboard_columns_base_scope
    Column.reconcile_broken_image_file_refs!(base_scope)

    target_ids = base_scope.merge(Column.missing_generated_image).where(id: column_ids).pluck(:id)
    if target_ids.size < column_ids.size
      return redirect_to columns_path, alert: "選択された記事の一部にアクセスできないか、画像生成の対象外です。"
    end

    if client_signed_in?
      remaining = current_client.plan_limits[:image_generations] - current_client.image_generation_usage_count
      if remaining <= 0
        return redirect_to columns_path, alert: current_client.plan_limit_message(:image_generation)
      end
      target_ids = target_ids.first(remaining)
    end

    if target_ids.any?
      @@bulk_image_generating = true
      truncated = client_signed_in? && column_ids.size > target_ids.size

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

      notice = "#{target_ids.size}件の画像自動生成処理をバックグラウンドで開始しました。"
      notice += "（プラン上限のため選択分の一部のみ処理）" if truncated
      redirect_to columns_path, notice: notice
    else
      redirect_to columns_path, alert: "対象となる画像未設定の記事が見つかりませんでした。"
    end
  end

  # ======================
  # GENERATION ACTIONS
  # ======================
  def draft
    @columns = dashboard_columns_base_scope
                 .where("body IS NULL OR TRIM(body) = ''")
                 .order(created_at: :desc)
  end

  def approve
    if @column.generated_body?
      return redirect_to dashboard_root_path, alert: Column::ALREADY_GENERATED_NOTICE
    end

    pending_ids = prepare_columns_for_generation!(@column.id)
    if pending_ids.blank?
      return redirect_to dashboard_root_path, alert: Column::ALREADY_GENERATED_NOTICE
    end

    spawn_sequential_body_generation!(pending_ids)
    Rails.logger.info("[ApproveGenerate] started column_id=#{@column.id}")

    redirect_to dashboard_root_path, notice: "本文生成を開始しました"
  end

  def publish
    unless @column.generated_body?
      return redirect_back fallback_location: dashboard_root_path, alert: "本文が生成されていないため公開できません"
    end

    @column.publish!
    Rails.logger.info("[Publish] column_id=#{@column.id}")
    redirect_back fallback_location: dashboard_root_path, notice: "記事を公開しました"
  end

  def unpublish
    @column.unpublish!
    Rails.logger.info("[Unpublish] column_id=#{@column.id}")
    redirect_back fallback_location: dashboard_root_path, notice: "記事を下書き（レビュー待ち）に戻しました"
  end

  def generate_pillar
    if params[:title].present?
      GptPillarGenerator.generate_full_article(params[:title], params[:genre], params[:choice])
      redirect_to draft_columns_path, notice: "ドラフト作成完了"
    else
      redirect_to new_column_path, alert: "タイトル未入力"
    end
  end

  def generate_from_selected
    ids = params[:column_ids]
    return redirect_to draft_columns_path, alert: "未選択" if ids.blank?

    scope = dashboard_columns_base_scope.where(id: ids, article_type: "pillar")
    if scope.with_generated_body.exists?
      return redirect_to draft_columns_path, alert: Column::ALREADY_GENERATED_NOTICE
    end

    target_ids = scope.pluck(:id)
    pending_ids = prepare_columns_for_generation!(target_ids)
    if pending_ids.blank?
      return redirect_to(draft_columns_path, alert: "対象の記事が見つかりませんでした")
    end

    spawn_sequential_body_generation!(pending_ids)
    Rails.logger.info("[GenerateFromSelected] started #{pending_ids.size} columns (ids=#{pending_ids.join(',')})")
    redirect_to draft_columns_path, notice: "生成開始"
  end

  def generate_title
    unless @column.article_type == "pillar"
      redirect_back fallback_location: pillar_manage_path(@column), alert: "親記事でのみ子タイトルを生成できます"
      return
    end

    return_path = pillar_manage_path(@column)
    remaining = remaining_child_slots_for(@column)

    if remaining <= 0
      message = @column.client&.plan_limit_message(:child) || "これ以上子記事を作成できません"
      redirect_back fallback_location: return_path, alert: message
      return
    end

    topic_plans = GptTitleGenerator.generate_titles(@column)

    if topic_plans.blank?
      redirect_back fallback_location: return_path, alert: "子タイトルの生成に失敗しました"
      return
    end

    topic_plans = topic_plans.first(remaining)

    ActiveRecord::Base.transaction do
      topic_plans.each do |plan|
        Column.create!(
          parent_id: @column.id,
          title: plan["title"],
          article_type: "child",
          status: "draft",
          genre: @column.genre,
          choice: @column.choice,
          client_id: @column.client_id
        )
      end
    end

    redirect_back fallback_location: return_path, notice: "#{topic_plans.size}件の子タイトルを作成しました（残り #{remaining - topic_plans.size} 件）"
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: return_path, alert: e.record.errors.full_messages.join(", ")
  end

  def create_child_title
    unless @column.article_type == "pillar"
      redirect_back fallback_location: pillar_manage_path(@column), alert: "親記事でのみ子タイトルを作成できます"
      return
    end

    title = params[:child_title].to_s.strip
    if title.blank?
      redirect_back fallback_location: pillar_manage_path(@column), alert: "子記事タイトルを入力してください"
      return
    end

    remaining = remaining_child_slots_for(@column)
    if remaining <= 0
      message = @column.client&.plan_limit_message(:child) || "これ以上子記事を作成できません"
      redirect_back fallback_location: pillar_manage_path(@column), alert: message
      return
    end

    child = Column.new(
      parent_id: @column.id,
      title: title,
      article_type: "child",
      status: "draft",
      genre: @column.genre,
      choice: @column.choice,
      client_id: @column.client_id
    )

    if child.save
      redirect_back fallback_location: pillar_manage_path(@column), notice: "子記事タイトルを追加しました"
    else
      redirect_back fallback_location: pillar_manage_path(@column), alert: child.errors.full_messages.join(", ")
    end
  end

  # ======================
  # PRIVATE
  # ======================
  private

  def redirect_legacy_columns_index!
    return if current_public_genre_key.present?

    # 管理画面は /columns のまま扱う（カスタムジャンルでも公開ルート制約に依存しない）
    return if columns_manage_view?

    genre_key = default_public_genre_key.to_s
    if genre_key.blank? || !routable_public_genre_key?(genre_key)
      raise ActiveRecord::RecordNotFound, "公開ジャンルが見つかりません"
    end

    redirect_to columns_index_path(request.query_parameters.symbolize_keys.merge(genre: genre_key))
  rescue ActionController::UrlGenerationError
    raise ActiveRecord::RecordNotFound, "公開ジャンルが見つかりません"
  end

  def resolve_columns_layout
    return "admin" if columns_manage_view? && %w[index show].include?(action_name)

    "application"
  end

  def set_column
    @column = Column.find_by(code: params[:id]) || Column.find_by(id: params[:id])
    raise ActiveRecord::RecordNotFound, "Couldn't find Column with code or id: #{params[:id]}" unless @column
  end

  def require_column_access!
    return if admin_signed_in?
    return if client_signed_in? && @column.client_id == current_client.id

    flash[:alert] = "指定された記事にアクセスできません。"
    redirect_to root_path
  end

  def require_readable_column!
    return if readable_column?(@column)

    raise ActiveRecord::RecordNotFound, "Couldn't find Column with code or id: #{params[:id]}"
  end

  def render_404
    render file: "#{Rails.root}/public/404.html", status: :not_found, layout: false
  end

  def set_breadcrumbs
    # トップ →（ブランドnginxが渡すLP）→ Genre名記事一覧 → 記事
    add_breadcrumb "トップ", "/"

    genre_key = (@column&.genre.presence || params[:genre]).to_s

    if platform_host? && genre_key == CrawlPolicy::GENRE_KEY
      add_breadcrumb "AI記事一覧", "/ai_article/columns"
    else
      # LPは Draftiy が知らない。ブランド側 nginx のヘッダーだけを信じる。
      if (lp = brand_lp_from_proxy_headers)
        add_breadcrumb lp[:label], lp[:path]
        add_breadcrumb "#{lp[:label]}記事一覧", "/columns"
      else
        genre_ja = GenreRegistry.to_ja(genre_key).presence || genre_key.presence || "記事"
        add_breadcrumb "#{genre_ja}記事一覧", consumer_columns_index_path(genre_key)
      end
    end

    return unless action_name == "show" && @column

    parent = @column.parent
    if parent&.publicly_visible? && parent.code.present?
      add_breadcrumb parent.title, consumer_column_show_path(parent)
    end
    add_breadcrumb @column.title
  end

  # ブランドnginxが渡す親LP。Draftiy側にブランド知識は持たない。
  #   X-Brand-Lp-Path:  /pages/cargo
  #   X-Brand-Lp-Label: 軽貨物
  def brand_lp_from_proxy_headers
    path = request.headers["X-Brand-Lp-Path"].to_s.strip.presence
    label = request.headers["X-Brand-Lp-Label"].to_s.strip.presence
    return nil if path.blank? || label.blank?
    return nil unless path.match?(%r{\A/[\w\-./%]*\z}) && !path.start_with?("//")

    label = CGI.unescape(label) if label.include?("%")
    { label: label, path: path }
  end

  # ブランドドメインでは nginx で /columns にフラット化されるため、パンくずも合わせる
  def consumer_columns_index_path(genre_key)
    return "/columns" unless platform_host?

    public_columns_index_path(genre: genre_key)
  end

  def consumer_column_show_path(column)
    return "/columns/#{column.code}" if !platform_host? && column.code.present?

    public_column_show_path(column)
  end

  def column_params
    params.require(:column).permit(
      :title, :file, :choice, :keyword, :description, :genre, :code,
      :body, :status, :article_type, :parent_id, :cluster_limit, :prompt, :sub_genre
    )
  end

  def assign_column_form_genre_options
    registry = column_form_genre_registry
    @column_form_genre_options = registry.map { |key, value| [value[:ja], key.to_s] }
    @column_form_sub_categories_json = registry.transform_values do |value|
      value[:sub_categories]&.map { |sub_key, sub_value| { id: sub_key, name: sub_value[:name] } } || []
    end.to_json
  end

  def column_form_genre_registry
    if admin_signed_in?
      GenreRegistry.genres
    elsif client_signed_in?
      client_accessible_genre_registry
    else
      GenreRegistry.genres
    end
  end

  def delete_bulk_fallback_path
    if params[:return_pillar_code].present?
      pillar = Column.find_by(code: params[:return_pillar_code])
      return pillar_manage_path(pillar) if pillar
    end

    if params[:return_pillar_id].present?
      pillar = Column.find_by(id: params[:return_pillar_id])
      return pillar_manage_path(pillar) if pillar
    end

    return draft_columns_path if params[:redirect_context] == "draft"

    dashboard_root_path
  end

  def prepare_columns_for_generation!(column_ids)
    ids = Array(column_ids).map(&:to_i).uniq
    return [] if ids.blank?

    pending_ids = Column.where(id: ids).merge(Column.without_generated_body).pluck(:id)
    return [] if pending_ids.blank?

    Column.where(id: pending_ids).update_all(
      status: "approved",
      generation_status: "queued",
      updated_at: Time.current
    )
    pending_ids
  end

  def spawn_sequential_body_generation!(column_ids)
    ids = Array(column_ids).map(&:to_i).uniq
    return if ids.blank?

    Thread.new do
      Rails.application.executor.wrap do
        ActiveRecord::Base.connection_pool.with_connection do
          ids.each do |column_id|
            begin
              column = Column.find_by(id: column_id)
              next if column.nil? || column.generated_body?

              GenerateColumnBodyJob.clear_cancellation!(column_id)
              GenerateColumnBodyJob.perform_now(column_id)
            rescue => e
              Rails.logger.error("[BodyGeneration] column_id=#{column_id} #{e.class}: #{e.message}")
            end
          end
        end
      end
    rescue => e
      Rails.logger.error("[BodyGeneration] thread error #{e.class}: #{e.message}")
    end
  end
end