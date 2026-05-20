class ColumnsController < ApplicationController
  before_action :set_column, only: [:show, :edit, :update, :destroy, :approve, :generate_from_pillar, :generate_title, :remove_image]
  before_action :set_breadcrumbs
  
  # スレッド多重実行を防止するアプリケーション変数
  @@bulk_image_generating = false

  def index
    # 1. ホスト判定：このドメインが許可する唯一のジャンルを確定させる
    @allowed_genre = case request.host
                     when "ri-plus.jp" then "app"
                     when "自販機.net" then "vender"
                     when "j-work.jp" then "cargo"
                     when "okey.work" then "cleaning"
                     when "kurasera.life" then "housekeeping"
                     else nil
                     end

    # 2. クエリ構築
    columns = Column
                .select(
                  :id,
                  :title,
                  :description,
                  :genre,
                  :article_type,
                  :updated_at,
                  :file,
                  :code,
                  :parent_id,
                  :status,
                  :sub_genre,
                  :sub_category
                )
                .where.not(status: "draft")
                .where.not(body: [nil, ""])

    # 3. 物理的排除
    if @allowed_genre.present?
      columns = columns.where(genre: @allowed_genre)

      if params[:genre].present? && params[:genre] != @allowed_genre
        return render_404
      end
    else
      columns = columns.where(genre: params[:genre]) if params[:genre].present?
    end

    # 4. 共通フィルタ
    columns = columns.where(status: params[:status]) if params[:status].present?
    columns = columns.where(article_type: params[:article_type]) if params[:article_type].present?

    if params[:selected_genre].present?
      columns = columns.where(genre: params[:selected_genre])
    end

    # 5. 並び順
    columns = columns.order(updated_at: :desc)

    # =========================================================================
    # メモリ逼迫対策
    # =========================================================================
    columns = columns.limit(30)

    # Relation のまま保持せず配列化
    @columns = columns.to_a

    # =========================================================================
    # Pillar の場合のみジャンルごとにグループ化
    # =========================================================================
    if params[:article_type] == "pillar"
      @grouped_columns = @columns.group_by(&:genre)

      @all_genres = Column
                      .where.not(status: "draft")
                      .distinct
                      .pluck(:genre)
                      .compact
    end

    # =========================================================================
    # 子記事カウント
    # =========================================================================
    if @columns.present?
      @child_counts = Column
                        .where.not(body: [nil, ""])
                        .where(parent_id: @columns.map(&:id))
                        .group(:parent_id)
                        .count
    else
      @child_counts = {}
    end

    # =========================================================================
    # ジャンル別カウント
    # =========================================================================
    base_count_query =
      if @allowed_genre.present?
        Column.where(genre: @allowed_genre)
      else
        Column.all
      end

    base_count_query = base_count_query
                         .where.not(status: "draft")
                         .where.not(body: [nil, ""])

    base_count_query = base_count_query.where(genre: params[:genre]) if params[:genre].present?
    base_count_query = base_count_query.where(genre: params[:selected_genre]) if params[:selected_genre].present?

    @genre_pillar_counts =
      base_count_query
        .where(article_type: "pillar")
        .group(:genre)
        .count

    @genre_child_counts =
      base_count_query
        .where(article_type: "child")
        .group(:genre)
        .count
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
        @children = @column.children.order(updated_at: :desc)
      else
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
  # IMAGE ACTIONS (NON-SIDEKIK THREAD BASE)
  # ======================
  
  # 画像単体削除アクション
  def remove_image
    if @column.respond_to?(:file) && @column.file.respond_to?(:purge)
      @column.file.purge
    else
      @column.update_column(:file, nil)
    end
    redirect_back fallback_location: columns_path, notice: "画像を削除しました。"
  end

  # JSON用カウントチェッカー
  def check_bulk_image_count
    genre = params[:bulk_genre]
    article_type = params[:bulk_article_type]

    query = Column.where(file: nil).where.not(body: [nil, ""])
    query = query.where(genre: genre) if genre.present?
    query = query.where(article_type: article_type) if article_type.present?

    render json: { count: query.count, is_running: @@bulk_image_generating }
  end

  # Sidekiqなしで動くネイティブスレッド一括自動生成
  def bulk_generate_images
    if @@bulk_image_generating
      return redirect_to columns_path, alert: "現在、別の一括画像生成タスクが実行中です。完了までお待ちください。"
    end

    genre = params[:bulk_genre]
    article_type = params[:bulk_article_type]

    query = Column.where(file: nil).where.not(body: [nil, ""])
    query = query.where(genre: genre) if genre.present?
    query = query.where(article_type: article_type) if article_type.present?

    target_ids = query.pluck(:id)

    if target_ids.any?
      @@bulk_image_generating = true

      # Sidekiqなどのキューシステムを完全に排除し、Rubyの軽量スレッドでプロセスを分離
      Thread.new do
        begin
          # スレッドプールからのDBコネクションを明示的に貸与・返却管理
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
          # タスク完了または異常終了時に確実にロックを解除
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