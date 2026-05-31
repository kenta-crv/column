class Dashboard::ColumnsController < ApplicationController
  before_action :authenticate_admin!

  # レイアウトは既存の "admin" をそのまま流用
  layout "admin"

def index
    # 1. 基本となるクエリを定義
    scope = Column.order(updated_at: :desc)

    # 2. params[:scope] に応じてクエリの条件を綺麗に切り替える
    if params[:scope].present?
      case params[:scope]
      when "draft"
        scope = scope.where(body: [nil, ""])
      when "pillar"
        scope = scope.where(article_type: "pillar")
      when "cluster"
        scope = scope.where(article_type: "cluster")
      when "published"
        scope = scope.where.not(body: [nil, ""])
      when "error"
        scope = scope.where(status: "error")
      end
    end

    # ジャンル絞り込み用セレクトボックスからの入力を反映
    if params[:genre].present?
      scope = scope.where(genre: params[:genre])
    end

    # 言語絞り込み用セレクトボックスからの入力を反映
    if params[:language].present?
      # ※もしカラム名が `lang` の場合は `where(lang: params[:language])` に書き換えてください
      scope = scope.where(language: params[:language])
    end

    # 3. 最後にページネーションを適用して代入
    @columns = scope.page(params[:page])

    @genre_pillar_counts = Column.pillars.group(:genre).count
    @genre_child_counts   = Column.clusters.group(:genre).count

    @grouped_columns = if params[:article_type] == "pillar"
                          @columns.group_by(&:genre)
                        end

    @all_genres = Column.distinct.pluck(:genre)

    # =========================================================================
    # Bパターン：過去24時間以内に更新されたレコードがある場合、通知ドットをONにする
    # =========================================================================
    @has_new_notifications = Column.where("updated_at > ?", 24.hours.ago).exists?
  end
    def bulk_generate_images
    BulkImageGeneratorService.call(
      genre: params[:bulk_genre],
      article_type: params[:bulk_article_type]
    )

    # リダイレクト先を dashboard のパスに変更
    redirect_to dashboard_columns_path, notice: "画像生成を開始しました"
  end

  def check_bulk_image_count
    scope = Column.all
    scope = scope.where(genre: params[:bulk_genre]) if params[:bulk_genre].present?
    scope = scope.where(article_type: params[:bulk_article_type]) if params[:bulk_article_type].present?

    scope = scope.where(file: [nil, ""])

    render json: {
      count: scope.count,
      is_running: BulkImageGeneratorService.running?
    }
  end

  def export
    # Ruby標準のCSVライブラリを確実にロード
    require "csv"

    # 1. 画面の絞り込みと完全に同じクエリ条件のベースを構築
    scope = Column.order(updated_at: :desc)

    if params[:scope].present?
      case params[:scope]
      when "draft"
        scope = scope.where(body: [nil, ""])
      when "pillar"
        scope = scope.where(article_type: "pillar")
      when "cluster"
        scope = scope.where(article_type: "cluster")
      when "published"
        scope = scope.where.not(body: [nil, ""])
      when "error"
        scope = scope.where(status: "error")
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
    column = Column.find(params[:id])
    column.update(file: nil)
    
    # リダイレクト先を dashboard のパスに変更
    redirect_to dashboard_columns_path
  end
end