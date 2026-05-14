class ColumnsController < ApplicationController
  before_action :set_column, only: [:show, :edit, :update, :destroy, :approve, :generate_from_pillar, :generate_title]
  before_action :set_breadcrumbs
  
  def index
    # 1. ホスト判定：このドメインが許可する唯一のジャンルを確定させる
    @allowed_genre = case request.host
                     when "ri-plus.jp"   then "app"
                     when "自販機.net"  then "vender"
                     when "j-work.jp"    then "cargo"
                     when "okey.work"    then "cleaning"
                     when "kurasera.life"    then "housekeeping"
                     else nil # column.okey.work 等のハブサイト
                     end

    # 2. クエリ構築：ベースは「公開済み」かつ「本文あり」
    columns = Column.where.not(status: "draft").where.not(body: [nil, ""])

    # 3. 物理的排除の実行
    if @allowed_genre.present?
      # 強制的にジャンルを固定
      columns = columns.where(genre: @allowed_genre)

      # URLパラメータで別のジャンルを叩こうとした場合は、不一致として404を返す
      if params[:genre].present? && params[:genre] != @allowed_genre
        return render_404
      end
    else
      # 制限がないハブサイト等の場合のみ、パラメータがあれば絞り込む
      columns = columns.where(genre: params[:genre]) if params[:genre].present?
    end

    # 4. 共通フィルタ
    columns = columns.where(status: params[:status]) if params[:status].present?
    columns = columns.where(article_type: params[:article_type]) if params[:article_type].present?
    
    # セレクトボックスで選択されたジャンルがある場合の絞り込み
    if params[:selected_genre].present?
      columns = columns.where(genre: params[:selected_genre])
    end

    @columns = columns.order(updated_at: :desc)

    # 親記事(pillar)が選択されている場合、ジャンルごとにグループ化する
    if params[:article_type] == 'pillar'
      @grouped_columns = @columns.group_by(&:genre)
      # セレクトボックス用の全ジャンルリスト（重複排除）
      @all_genres = Column.where.not(status: "draft").pluck(:genre).uniq.compact
    end

    # 子記事カウント
    column_ids = @columns.pluck(:id)
    @child_counts = column_ids.any? ? Column.where(parent_id: column_ids).where.not(body: [nil, ""]).group(:parent_id).count : {}
  end

  def show
    # 1. 閲覧ドメインの許可ジャンルを再判定
    allowed_for_show = case request.host
                       when "ri-plus.jp"   then "app"
                       when "自販機.net"  then "vender"
                       when "j-work.jp"    then "cargo"
                       when "okey.work"    then "cleaning"
                       when "kurasera.life"    then "housekeeping"
                       else nil
                       end

    # 2. 記事のジャンルがドメイン許可と不一致なら即404（物理的シャットアウト）
    if allowed_for_show.present? && @column.genre != allowed_for_show
      return render_404
    end

    # 3. URL正規化（301リダイレクト）
    expected_path = columns_show_path(genre: @column.genre, id: @column.code)
    if request.path != expected_path
      return redirect_to expected_path, status: :moved_permanently
    end

    # 4. 表示用データの準備
    if @column.article_type == "pillar"
      if admin_signed_in?
        # 管理者は生成用の下書き（本文なし）も含めてすべて表示
        @children = @column.children.order(updated_at: :desc)
      else
        # 一般ユーザーには公開済みで本文があるものだけを表示
        @children = @column.children.where.not(status: "draft").where.not(body: [nil, ""]).order(updated_at: :desc)
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
      idx = @headings.size
      @headings << { tag: tag, text: text, id: "heading-#{idx}", level: tag[1].to_i }
      "<#{tag} id='heading-#{idx}'>#{text}</#{tag}>"
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
end