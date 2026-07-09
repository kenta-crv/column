class Api::V1::ArticlesController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_client
  before_action :require_api_access!

  def index
    columns = client_articles_scope.order(updated_at: :desc)

    render json: columns.map { |c| article_json(c) }
  end

  def show
    column = client_articles_scope.find(params[:id])
    render json: article_json(column)
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Article not found' }, status: :not_found
  end

  def render_html
    if params[:column].present?
      @column = client_articles_scope
                 .find_by(code: params[:column]) || client_articles_scope.find_by(id: params[:column])

      if @column.nil?
        render content_type: 'text/html', body: '<div style="padding:20px;color:red;">記事が見つかりません。</div>'
        return
      end

      @column_body_with_ids = @column.body
      @headings = extract_headings(@column.body)
      @children = client_articles_scope.where(article_type: %w[child cluster], parent_id: @column.id)

      html = render_to_string(
        partial: 'api/v1/articles/show',
        locals: { column: @column, base_url: request.base_url }
      )
    else
      @columns = client_articles_scope.order(updated_at: :desc)

      html = render_to_string(
        partial: 'api/v1/articles/articles',
        locals: { columns: @columns, base_url: request.base_url }
      )
    end

    if html.nil?
      render content_type: 'text/html', body: '<div style="padding:20px;color:red;">表示するコンテンツがありません。</div>'
      return
    end

    base_url = request.base_url
    processed_html = html.gsub('src="/', "src=\"#{base_url}/")
                         .gsub('href="/', "href=\"#{base_url}/")

    render content_type: 'text/html', body: processed_html
  end

  private

  def client_articles_scope
    Column.where(client_id: @client.id)
          .where.not(body: [nil, ""])
          .where(genre: @client.genre_keys)
  end

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

  def require_api_access!
    return if @client.can_use_api?

    render json: { error: @client.plan_limit_message(:api) }, status: :forbidden
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
