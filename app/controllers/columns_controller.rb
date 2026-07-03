class ColumnsController < ApplicationController
  before_action :set_column, only: [:show, :edit, :update, :destroy, :approve, :generate_title, :remove_image]
  before_action :set_breadcrumbs
  before_action :assign_column_form_genre_options, only: [:new, :create, :edit, :update]
  
  @@bulk_image_generating = false

def index
  effective_genre = resolve_public_genre_filter

  columns = Column
              .where("body IS NOT NULL AND TRIM(body) != ''")
              .select(
                :id, :title, :description, :body,
                :genre, :article_type, :updated_at,
                :file, :code, :parent_id, :status,
                :sub_genre, :sub_category
              )

  if params[:q].present?
    columns = columns.where(
      "title LIKE ? OR keyword LIKE ? OR description LIKE ?",
      "%#{params[:q]}%", "%#{params[:q]}%", "%#{params[:q]}%"
    )
  end

  columns = columns.where(genre: effective_genre)                if effective_genre.present?
  columns = columns.where(article_type: params[:article_type])  if params[:article_type].present?
  columns = columns.where(genre: params[:selected_genre])       if params[:selected_genre].present?

  columns = columns.order(updated_at: :desc)

  @paginated_columns = columns.page(params[:page]).per(30)
  @columns = @paginated_columns.to_a

  if params[:article_type] == "pillar"
    @grouped_columns = @columns.group_by(&:genre)

    @all_genres = Column
                    .where("body IS NOT NULL AND TRIM(body) != ''")
                    .distinct
                    .pluck(:genre)
                    .compact
  end

  if @columns.present?
    @child_counts = Column
                      .where("body IS NOT NULL AND TRIM(body) != ''")
                      .where(parent_id: @columns.map(&:id))
                      .group(:parent_id)
                      .count
  else
    @child_counts = {}
  end

  base_count_query = Column.where("body IS NOT NULL AND TRIM(body) != ''")

  if params[:q].present?
    base_count_query = base_count_query.where(
      "title LIKE ? OR keyword LIKE ? OR description LIKE ?",
      "%#{params[:q]}%", "%#{params[:q]}%", "%#{params[:q]}%"
    )
  end

  base_count_query = base_count_query.where(genre: effective_genre)          if effective_genre.present?
  base_count_query = base_count_query.where(genre: params[:selected_genre]) if params[:selected_genre].present?

  @genre_pillar_counts = base_count_query.where(article_type: "pillar").group(:genre).count
  @genre_child_counts  = base_count_query.where(article_type: "child").group(:genre).count

  @current_genre_key = effective_genre  # ビュー側でタイトル生成に使う
end

  def show
    current_genre_key = if defined?(GenreRegistry) && GenreRegistry.respond_to?(:from_ja)
                          GenreRegistry.from_ja(@column.genre)
                        end
    current_genre_key ||= @column.genre.to_s.strip.downcase

    if @column.article_type == "pillar"
      if admin_signed_in?
        @children = @column.children.order(updated_at: :desc)
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
    return redirect_to(draft_columns_path) if column_ids.blank?

    case params[:action_type]
    when "approve_bulk"
      Column.where(id: column_ids).find_each do |c|
        GenerateColumnBodyJob.perform_later(c.id)
      end
      redirect_to columns_path

    when "delete_bulk"
      Column.where(id: column_ids).destroy_all
      redirect_to draft_columns_path
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

    unless admin_or_allowed_genre?(@column.genre)
      @column.errors.add(:genre, "は利用できません")
      render :new, status: :unprocessable_entity
      return
    end

    if @column.save
      redirect_to columns_path, notice: "作成しました"
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
      redirect_to columns_path, notice: "更新しました"
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
    if @column.respond_to?(:file) && @column.file.respond_to?(:purge)
      @column.file.purge
    else
      @column.update_column(:file, nil)
    end
    redirect_back fallback_location: columns_path, notice: "画像を削除しました。"
  end

  def check_bulk_image_count
    genre        = params[:bulk_genre]
    article_type = params[:bulk_article_type]

    query = Column
              .where("body IS NOT NULL AND TRIM(body) != ''")
              .where(file: nil)

    query = query.where(genre: genre)               if genre.present?
    query = query.where(article_type: article_type) if article_type.present?

    render json: { count: query.count, is_running: @@bulk_image_generating }
  end

  def bulk_generate_images
    if @@bulk_image_generating
      return redirect_to columns_path, alert: "現在、別の一括画像生成タスクが実行中です。完了までお待ちください。"
    end

    genre        = params[:bulk_genre]
    article_type = params[:bulk_article_type]

    query = Column
              .where("body IS NOT NULL AND TRIM(body) != ''")
              .where(file: nil)

    query = query.where(genre: genre)               if genre.present?
    query = query.where(article_type: article_type) if article_type.present?

    target_ids = query.pluck(:id)

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

      redirect_to columns_path, notice: "#{target_ids.size}件の画像自動生成処理をバックグラウンドで開始しました。"
    else
      redirect_to columns_path, alert: "対象となる画像未設定の記事が見つかりませんでした。"
    end
  end

  # ======================
  # GENERATION ACTIONS
  # ======================
  def draft
    @columns = Column
                 .where("body IS NULL OR TRIM(body) = ''")
                 .order(created_at: :desc)
  end

  def approve
    unless @column.approved?
      @column.update!(status: "approved")
      GenerateColumnBodyJob.perform_later(@column.id)
    end
    redirect_to columns_path, notice: "承認しました。"
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

    Column.where(id: ids, article_type: "pillar")
          .each { |c| GenerateColumnBodyJob.perform_later(c.id) }

    redirect_to draft_columns_path, notice: "生成開始"
  end

  def generate_title
    topic_plans = GptTitleGenerator.generate_titles(@column)

    if topic_plans.any?
      ActiveRecord::Base.transaction do
        topic_plans.each do |plan|
          Column.create!(
            parent_id: @column.id,
            title: plan["title"],
            article_type: "child",
            status: "draft",
            genre: @column.genre,
            choice: @column.choice
          )
        end
      end

      redirect_to columns_show_path(genre: @column.genre, id: @column.code),
                  notice: "#{topic_plans.size}件生成しました"
    else
      redirect_to columns_show_path(genre: @column.genre, id: @column.code),
                  alert: "生成失敗"
    end
  end

  # ======================
  # PRIVATE
  # ======================
  private

  def set_column
    @column = Column.find_by(code: params[:id]) || Column.find_by(id: params[:id])
    raise ActiveRecord::RecordNotFound, "Couldn't find Column with code or id: #{params[:id]}" unless @column
  end

  def render_404
    render file: "#{Rails.root}/public/404.html", status: :not_found, layout: false
  end

  def set_breadcrumbs
    add_breadcrumb 'トップ'

    genre_key = @column&.genre.present? ? @column.genre : params[:genre]

    if defined?(LpDefinition)
      label = LpDefinition.label(genre_key)
      add_breadcrumb label, "/#{genre_key}" if label
    end

    add_breadcrumb @column.title if action_name == 'show' && @column
  end

  def column_params
    params.require(:column).permit(
      :title, :file, :choice, :keyword, :description, :genre, :code,
      :body, :status, :article_type, :parent_id, :cluster_limit, :prompt, :sub_genre
    )
  end

  def resolve_public_genre_filter
    return params[:genre].to_s if params[:genre].present?

    # drafity.pro はメインプラットフォーム。/columns では全ジャンルを表示する
    return nil if main_platform_host?(request.host)

    GenreRegistry.allowed_hosts(request.host)&.to_s
  end

  def main_platform_host?(host)
    host.to_s.downcase.sub(/\Awww\./, "") == "drafity.pro"
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
end