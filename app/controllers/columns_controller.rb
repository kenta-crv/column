class ColumnsController < ApplicationController
  before_action :authenticate_admin_or_client!, except: [:index, :show]
  before_action :authenticate_admin_or_client!, only: [:bulk_update_drafts]
  before_action :redirect_legacy_columns_index!, only: [:index]
  before_action :set_column, only: [:show, :edit, :update, :destroy, :approve, :generate_title, :remove_image, :create_child_title]
  before_action :require_readable_column!, only: [:show]
  before_action :require_column_access!, only: [:edit, :update, :destroy, :approve, :generate_title, :remove_image, :create_child_title]
  before_action :set_breadcrumbs
  before_action :assign_column_form_genre_options, only: [:new, :create, :edit, :update]
  
  @@bulk_image_generating = false

def index
  columns = public_readable_columns_scope.select(
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

  columns = columns.where(article_type: params[:article_type])  if params[:article_type].present?
  columns = columns.where(genre: params[:selected_genre])       if params[:selected_genre].present?

  columns = columns.order(updated_at: :desc)

  @paginated_columns = columns.page(params[:page]).per(30)
  @columns = @paginated_columns.to_a

  if params[:article_type] == "pillar"
    @grouped_columns = @columns.group_by(&:genre)

    @all_genres = public_readable_columns_scope.distinct.pluck(:genre).compact
  end

  if @columns.present?
    column_ids = @columns.map(&:id)
    @child_counts = public_readable_columns_scope
                      .where(parent_id: column_ids)
                      .group(:parent_id)
                      .count
  else
    @child_counts = {}
  end

  base_count_query = public_readable_columns_scope

  if params[:q].present?
    base_count_query = base_count_query.where(
      "title LIKE ? OR keyword LIKE ? OR description LIKE ?",
      "%#{params[:q]}%", "%#{params[:q]}%", "%#{params[:q]}%"
    )
  end

  base_count_query = base_count_query.where(genre: params[:selected_genre]) if params[:selected_genre].present?

  @genre_pillar_counts = base_count_query.where(article_type: "pillar").group(:genre).count
  @genre_child_counts  = base_count_query.where(article_type: "child").group(:genre).count

  @current_genre_key = current_public_genre_key
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
        @children = @column.children.where("body IS NOT NULL AND TRIM(body) != ''").order(updated_at: :desc)
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

    case params[:action_type]
    when "approve_bulk"
      scope.find_each do |c|
        GenerateColumnBodyJob.perform_later(c.id)
      end
      redirect_to dashboard_root_path, notice: "本文生成を開始しました"

    when "delete_bulk"
      scope.destroy_all
      redirect_to delete_bulk_fallback_path, notice: "選択した子記事を削除しました"
    else
      redirect_to delete_bulk_fallback_path, alert: "不正な操作です"
    end
  end

  # ======================
  # CRUD
  # ======================
  def new
    @column = Column.new(article_type: client_signed_in? ? "pillar" : nil)
  end

  def create
    @column = Column.new(column_params)
    assign_column_client!(@column)

    unless admin_or_allowed_genre?(@column.genre)
      @column.errors.add(:genre, "は利用できません")
      render :new, status: :unprocessable_entity
      return
    end

    if @column.save
      redirect_to public_columns_index_path(genre: @column.genre), notice: "作成しました"
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
      redirect_to public_columns_index_path(genre: @column.genre), notice: "更新しました"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    genre_key = @column.genre
    @column.destroy
    redirect_to public_columns_index_path(genre: genre_key), notice: "削除しました"
  end

  # ======================
  # IMAGE ACTIONS (NON-SIDEKIQ THREAD BASE)
  # ======================
  
  def remove_image
    if @column.respond_to?(:file) && @column.file.respond_to?(:purge)
      @column.file.purge
    else
      @column.update_column(:file, nil)
    end
    redirect_back fallback_location: public_columns_index_path(genre: @column.genre), notice: "画像を削除しました。"
  end

  def check_bulk_image_count
    genre        = params[:bulk_genre]
    article_type = params[:bulk_article_type]

    query = dashboard_columns_base_scope
              .where("body IS NOT NULL AND TRIM(body) != ''")
              .where(file: nil)

    query = query.where(genre: genre)               if genre.present? && admin_or_allowed_genre?(genre)
    query = query.where(article_type: article_type) if article_type.present?

    render json: { count: query.count, is_running: @@bulk_image_generating }
  end

  def bulk_generate_images
    if @@bulk_image_generating
      return redirect_to public_columns_index_path, alert: "現在、別の一括画像生成タスクが実行中です。完了までお待ちください。"
    end

    genre        = params[:bulk_genre]
    article_type = params[:bulk_article_type]

    query = dashboard_columns_base_scope
              .where("body IS NOT NULL AND TRIM(body) != ''")
              .where(file: nil)

    query = query.where(genre: genre)               if genre.present? && admin_or_allowed_genre?(genre)
    query = query.where(article_type: article_type) if article_type.present?

    target_ids = query.pluck(:id)

    if client_signed_in?
      remaining = current_client.plan_limits[:image_generations] - current_client.image_generation_usage_count
      if remaining <= 0
        return redirect_to public_columns_index_path, alert: current_client.plan_limit_message(:image_generation)
      end
      target_ids = target_ids.first(remaining)
    end

    if target_ids.any?
      @@bulk_image_generating = true

      Thread.new do
        begin
          ActiveRecord::Base.connection_pool.with_connection do
            Column.where(id: target_ids, file: nil).find_each do |column|
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

      redirect_to public_columns_index_path, notice: "#{target_ids.size}件の画像自動生成処理をバックグラウンドで開始しました。"
    else
      redirect_to public_columns_index_path, alert: "対象となる画像未設定の記事が見つかりませんでした。"
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
    unless @column.approved?
      @column.update!(status: "approved")
      GenerateColumnBodyJob.perform_later(@column.id)
    end
    redirect_to public_columns_index_path(genre: @column.genre), notice: "承認しました。"
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

    dashboard_columns_base_scope
      .where(id: ids, article_type: "pillar")
      .find_each { |c| GenerateColumnBodyJob.perform_later(c.id) }

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

    genre_key = default_public_genre_key
    raise ActiveRecord::RecordNotFound, "公開ジャンルが見つかりません" if genre_key.blank?

    redirect_to columns_index_path(request.query_parameters.symbolize_keys.merge(genre: genre_key))
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
    add_breadcrumb 'トップ'

    genre_key = @column&.genre.present? ? @column.genre : params[:genre]

    if defined?(LpDefinition)
      label = LpDefinition.label(genre_key)
      add_breadcrumb label, columns_index_path(genre: genre_key) if label && genre_key.present?
    end

    add_breadcrumb @column.title if action_name == 'show' && @column
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
end