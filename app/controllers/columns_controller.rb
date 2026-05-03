class ColumnsController < ApplicationController
  before_action :set_column, only: [:show, :edit, :update, :destroy, :approve]
  before_action :set_breadcrumbs
  before_action :set_noindex

def index
  @allowed_genre = GenreRegistry.allowed_hosts(request.host)

  columns = Column.where.not(status: "draft").where.not(body: [nil, ""])

  if @allowed_genre.present?
    columns = columns.where(genre: @allowed_genre)

    if params[:genre].present? && params[:genre] != @allowed_genre
      return render_404
    end
  else
    columns = columns.where(genre: params[:genre]) if params[:genre].present?
  end

  columns = columns.where(status: params[:status]) if params[:status].present?
  columns = columns.where(article_type: params[:article_type]) if params[:article_type].present?

  if params[:selected_genre].present?
    columns = columns.where(genre: params[:selected_genre])
  end

  @columns = columns.order(updated_at: :desc)

  if params[:article_type] == 'pillar'
    @grouped_columns = @columns.group_by(&:genre)
    @all_genres = Column.where.not(status: "draft").pluck(:genre).uniq.compact
  end

  column_ids = @columns.pluck(:id)
  @child_counts =
    column_ids.any? ?
      Column.where(parent_id: column_ids)
            .where.not(body: [nil, ""])
            .group(:parent_id).count : {}
end

def show
  # @column は before_action 等で find_by!(code: params[:id]) されている前提、
  # もしくはメソッド冒頭で @column = Column.find_by!(code: params[:id]) を追記してください

  allowed_for_show = GenreRegistry.allowed_hosts(request.host)

  if allowed_for_show.present? && @column.genre != allowed_for_show
    return render_404
  end

  if allowed_for_show.present?
    correct_path = columns_show_path(genre: @column.genre, id: @column.code)
    return redirect_to correct_path, status: :moved_permanently if request.path != correct_path
  elsif request.host.include?("column.okey.work")
    correct_path = column_path(@column)
    return redirect_to correct_path, status: :moved_permanently if request.path != correct_path
  end

  # ==============================
  # @children 取得ロジックの修正
  # ==============================
  @children =
    if @column.article_type == "pillar"
      if admin_signed_in?
        # 管理者の場合は、ドラフトや本文なしも含めてすべて表示
        @column.children.order(created_at: :desc)
      else
        # 一般ユーザーは、既存の通りドラフトと本文なしを除外
        @column.children.where.not(status: "draft").where.not(body: [nil, ""]).order(updated_at: :desc)
      end
    else
      []
    end

  markdown_body = @column.body.presence || "## 記事はまだ生成されていません。"
  raw_html_body = Kramdown::Document.new(markdown_body).to_html

  sanitized_html_body =
    raw_html_body.gsub(/<span[^>]*>|<\/span>/, '').gsub(/ style=\"[^\"]*\"/, '')

  @headings = []

  @column_body_with_ids =
    sanitized_html_body.gsub(/<(h[2-4])>(.*?)<\/\1>/m) do
      tag = Regexp.last_match(1)
      text = Regexp.last_match(2)

      idx = @headings.size

      @headings << {
        tag: tag,
        text: text,
        id: "heading-#{idx}",
        level: tag[1].to_i
      }

      "<#{tag} id='heading-#{idx}'>#{text}</#{tag}>"
    end
end

  # --- 管理用 ---
  def new; @column = Column.new; end
  def create
    @column = Column.new(column_params)
    if @column.save; redirect_to columns_path, notice: "作成しました"; else; render 'new'; end
  end
  def edit; add_breadcrumb "記事編集", edit_column_path(@column); end
  def update
    if @column.update(column_params); redirect_to columns_path, notice: "更新しました"; else; render 'edit'; end
  end
  def destroy; @column.destroy; redirect_to columns_path, notice: "削除しました"; end

  def generate_gemini
    batch = params[:batch] || 20
    created = GeminiColumnGenerator.generate_columns(batch_count: batch.to_i)
    redirect_to draft_columns_path, notice: "#{created}件生成しました"
  end

  def draft
    @columns = Column.where(status: "draft").or(Column.where(body: [nil, ""])).order(created_at: :desc)
  end

  def approve
    unless @column.approved?
      @column.update!(status: "approved")
      GenerateColumnBodyJob.perform_later(@column.id)
    end
    redirect_to columns_path, notice: "承認しました。"
  end

  def bulk_update_drafts
    column_ids = params[:column_ids]
    return redirect_to draft_columns_path, alert: "対象未選択" if column_ids.blank?
    case params[:action_type]
    when "approve_bulk"
      Column.where(id: column_ids).each { |c| GenerateColumnBodyJob.perform_later(c.id) }
      redirect_to columns_path, notice: "生成開始"
    when "delete_bulk"
      count = Column.where(id: column_ids).destroy_all
      redirect_to draft_columns_path, notice: "#{count}件削除"
    end
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
    Column.where(id: ids, article_type: "pillar").each { |c| GenerateColumnBodyJob.perform_later(c.id) }
    redirect_to draft_columns_path, notice: "生成開始"
  end

  def generate_from_pillar
    @column = Column.find_by(id: params[:id]) || Column.find_by!(code: params[:id])
    GenerateChildColumnsJob.perform_later(@column.id, 25)
    redirect_to column_path(@column), notice: "子記事生成開始"
  end

def generate_title
    @column = Column.find_by!(code: params[:id])
    
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
      # 階層化パスへリダイレクト
      redirect_to columns_show_path(genre: @column.genre, id: @column.code), notice: "#{topic_plans.size}件のクラスター記事案を生成しました。"
    else
      redirect_to columns_show_path(genre: @column.genre, id: @column.code), alert: "記事案の生成に失敗しました。"
    end
  end
  private

  def set_column; @column = Column.friendly.find(params[:id]); end
  def set_noindex; @noindex = params[:genre].blank?; end
  def render_404; render file: "#{Rails.root}/public/404.html", status: :not_found, layout: false; end

  def set_breadcrumbs
    add_breadcrumb 'トップ'
    genre_key = @column&.genre.present? ? @column.genre : params[:genre]
    if defined?(LpDefinition)
      label = LpDefinition.label(genre_key)
      add_breadcrumb label, "/#{genre_key}" if label
    end
    add_breadcrumb @column.title if action_name == 'show' && @column
  end

  def set_noindex
    @noindex = request.host == "column.okey.work"
  end

  def column_params
    params.require(:column).permit(
      :title, :file, :choice, :keyword, :description, :genre, :code, 
      :body, :status, :article_type, :parent_id, :cluster_limit, :prompt
    )
  end
end