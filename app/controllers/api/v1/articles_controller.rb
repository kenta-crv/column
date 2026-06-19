class Api::V1::ArticlesController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_client

  def index
    columns = Column.where(genre: @client.allowed_genres)
                   .where.not(body: [nil, ""])
                   .order(updated_at: :desc)
    
    render json: columns.map { |c| article_json(c) }
  end

  def show
    column = Column.find(params[:id])
    
    unless @client.allowed_genres.include?(column.genre)
      render json: { error: 'Genre not allowed' }, status: :forbidden
      return
    end
    
    render json: article_json(column)
  end

  def render_html
    # statusの縛りを排除して、該当ジャンルかつ本文ありの記事を取得
    columns = Column.unscope(:where)
                   .where(genre: @client.allowed_genres)
                   .where.not(body: [nil, ""])
                   .order(updated_at: :desc)
    
    # 修正したインラインスタイル付きの部分テンプレートをレンダリング
    html = render_to_string(
      partial: 'api/v1/articles/articles',
      locals: { columns: columns }
    )
    
    # 余計なアセット加工を挟まず、HTML文字列そのものを返却
    render content_type: 'text/html', body: html
  end

  private

  def authenticate_client
    api_key = request.headers['X-API-Key'] || params[:api_key]
    @client = Client.find_by(api_key: api_key)
    
    unless @client
      render json: { error: 'Invalid API key' }, status: :unauthorized
    end
  end

  def article_json(column)
    {
      id: column.id,
      title: column.title,
      body: column.body,
      description: column.description,
      genre: column.genre,
      sub_genre: column.sub_genre,
      code: column.code,
      keyword: column.keyword,
      status: column.status,
      article_type: column.article_type,
      file_url: column.file&.url,
      created_at: column.created_at,
      updated_at: column.updated_at
    }
  end
end