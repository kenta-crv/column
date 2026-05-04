class ColumnsController < ApplicationController
  before_action :set_column, only: [:show, :edit, :update, :destroy, :approve, :generate_from_pillar, :generate_title]
  before_action :set_breadcrumbs
  before_action :set_noindex

  # ======================
  # INDEX
  # ======================
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

    @columns = columns.order(updated_at: :desc)

    column_ids = @columns.pluck(:id)
    @child_counts =
      column_ids.any? ?
        Column.where(parent_id: column_ids)
              .where.not(body: [nil, ""])
              .group(:parent_id).count : {}
  end

  # ======================
  # SHOW（核心修正）
  # ======================
  def show
    allowed_for_show = GenreRegistry.allowed_hosts(request.host)

    if allowed_for_show.present? && @column.genre != allowed_for_show
      return render_404
    end

    # ★ 正規URLへ統一（column_path完全廃止）
    correct_path = columns_show_path(genre: @column.genre, id: @column.code)

    if request.path != correct_path
      return redirect_to correct_path, status: :moved_permanently
    end

    # children取得
    @children =
      if @column.article_type == "pillar"
        if admin_signed_in?
          @column.children.order(created_at: :desc)
        else
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

  # ======================
  # CRUD
  # ======================
  def new
    @column = Column.new
  end

  def create
    @column = Column.new(column_params)
    if @column.save
      redirect_to columns_path, notice: "作成しました"
    else
      render 'new'
    end
  end

  def edit
    add_breadcrumb "記事編集", edit_column_path(@column)
  end

  def update
    if @column.update(column_params)
      redirect_to columns_path, notice: "更新しました"
    else
      render 'edit'
    end
  end

  def destroy
    @column.destroy
    redirect_to columns_path, notice: "削除しました"
  end

  # ======================
  # GENERATION ACTIONS
  # ======================
  def generate_gemini
    batch = params[:batch] || 20
    created = GeminiColumnGenerator.generate_columns(batch_count: batch.to_i)
    redirect_to draft_columns_path, notice: "#{created}件生成しました"
  end

  def draft
    @columns = Column.where(status: "draft")
                     .or(Column.where(body: [nil, ""]))
                     .order(created_at: :desc)
  end

  def approve
    unless @column.approved?
      @column.update!(status: "approved")
      GenerateColumnBodyJob.perform_later(@column.id)
    end
    redirect_to columns_path, notice: "承認しました。"
  end

  def generate_from_selected
    ids = params[:column_ids]
    return redirect_to draft_columns_path, alert: "未選択" if ids.blank?

    Column.where(id: ids, article_type: "pillar")
          .each { |c| GenerateColumnBodyJob.perform_later(c.id) }

    redirect_to draft_columns_path, notice: "生成開始"
  end

  def generate_from_pillar
    GenerateChildColumnsJob.perform_later(@column.id, 25)
    redirect_to columns_show_path(genre: @column.genre, id: @column.code), notice: "子記事生成開始"
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
    @column = Column.find_by!(code: params[:id])
  end

  def set_noindex
    @noindex = GenreRegistry.allowed_hosts(request.host).blank?
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
      :body, :status, :article_type, :parent_id, :cluster_limit, :prompt
    )
  end
end