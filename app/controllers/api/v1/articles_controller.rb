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
    if params[:column].present?
      @column = Column.unscope(:where)
                     .where(genre: @client.allowed_genres)
                     .find_by(code: params[:column]) || Column.unscope(:where).where(genre: @client.allowed_genres).find_by(id: params[:column])

      if @column.nil?
        render content_type: 'text/html', body: '<div style="padding:20px;color:red;">記事が見つかりません。</div>'
        return
      end

      @column_body_with_ids = @column.body
      @headings = extract_headings(@column.body)
      @children = Column.where(article_type: "child", genre: @column.genre)

      html = render_to_string(
        partial: 'api/v1/articles/show',
        locals: { column: @column }
      )
    else
      columns = Column.unscope(:where)
                     .where(genre: @client.allowed_genres)
                     .where.not(body: [nil, ""])
                     .order(updated_at: :desc)
      
      html = render_to_string(
        partial: 'api/v1/articles/articles',
        locals: { columns: columns }
      )
    end

    # 💡 "http://localhost:3001" の固定を廃止し、アクセスされた環境のプロトコルとドメイン名を動的に取得
    base_url = "#{request.protocol}#{request.host_with_port}"
    processed_html = html.gsub('src="/', "src=\"#{base_url}/")
                         .gsub('href="/', "href=\"#{base_url}/")

    render content_type: 'text/html', body: processed_html
  end

  private

  def extract_headings(body)
    return [] if body.blank?

    html = Kramdown::Document.new(body.to_s).to_html
    fragment = Nokogiri::HTML::DocumentFragment.parse(html)

    fragment.css('h2, h3, h4').map do |node|
      {
        level: node.name[1].to_i,
        text:  node.text.strip,
        id:    node['id']
      }
    end
  end

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