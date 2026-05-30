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

    # 3. 最後にページネーションを適用して代入
    @columns = scope.page(params[:page])

    @genre_pillar_counts = Column.pillars.group(:genre).count
    @genre_child_counts   = Column.clusters.group(:genre).count

    @grouped_columns = if params[:article_type] == "pillar"
                          @columns.group_by(&:genre)
                        end

    @all_genres = Column.distinct.pluck(:genre)
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

  def remove_image
    column = Column.find(params[:id])
    column.update(file: nil)
    
    # リダイレクト先を dashboard のパスに変更
    redirect_to dashboard_columns_path
  end
end