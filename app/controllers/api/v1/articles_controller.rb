class Api::V1::ArticlesController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_client
  before_action :require_api_access!

  def index
    if params[:updated_since].present? && parsed_updated_since.nil?
      render json: { error: 'Invalid updated_since format. Use ISO8601 (e.g. 2026-07-01T00:00:00+09:00)' }, status: :bad_request
      return
    end

    columns = client_articles_scope.order(updated_at: :desc)
    columns = columns.where(genre: filter_genre_values) if params[:genre].present?
    columns = columns.where(article_type: params[:article_type]) if params[:article_type].present?
    columns = columns.where(updated_at: parsed_updated_since..) if params[:updated_since].present?

    page = [params[:page].to_i, 1].max
    per_page = params[:per_page].present? ? params[:per_page].to_i.clamp(1, 100) : 50

    total_count = columns.count
    columns = columns.offset((page - 1) * per_page).limit(per_page)

    render json: {
      articles: columns.map { |c| article_json(c) },
      pagination: {
        page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: (total_count.to_f / per_page).ceil
      }
    }
  end

  def show
    column = client_articles_scope.find_by(code: params[:code])
    column ||= client_articles_scope.find_by(id: params[:code])

    if column.nil?
      render json: { error: 'Article not found' }, status: :not_found
      return
    end

    render json: article_json(column)
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
      html = append_attribution_html(html, column: @column)
    else
      @columns = client_articles_scope.order(updated_at: :desc)

      html = render_to_string(
        partial: 'api/v1/articles/articles',
        locals: { columns: @columns, base_url: request.base_url }
      )
      html = append_attribution_html(html)
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
          .merge(Column.published)
          .where(genre: allowed_genre_values)
  end

  def allowed_genre_values
    @client.service_genres.flat_map do |genre|
      GenreRegistry.equivalent_keys(genre.key) + [genre.ja]
    end.compact.uniq
  end

  def filter_genre_values
    param = params[:genre].to_s
    matching_genre = @client.service_genres.find do |genre|
      GenreRegistry.equivalent_keys(genre.key).include?(param) || genre.ja == param
    end

    if matching_genre
      (GenreRegistry.equivalent_keys(matching_genre.key) + [matching_genre.ja]).compact.uniq
    else
      GenreRegistry.equivalent_keys(param).presence || [param]
    end
  end

  def parsed_updated_since
    @parsed_updated_since ||= begin
      Time.zone.parse(params[:updated_since].to_s)
    rescue ArgumentError, TypeError
      nil
    end
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
    payload = {
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
      published_at: column.published_at,
      created_at: column.created_at,
      updated_at: column.updated_at
    }

    if AttributionPolicy.required?(client: @client, genre: column.genre, column: column)
      attr = AttributionPolicy.payload(base_url: request.base_url)
      payload[:attribution_required] = true
      payload[:attribution] = {
        text: attr[:text],
        url: attr[:url],
        html: attr[:html]
      }
    else
      payload[:attribution_required] = false
      payload[:attribution] = nil
    end

    payload
  end

  def append_attribution_html(html, column: nil)
    return html unless AttributionPolicy.required?(client: @client, genre: column&.genre, column: column)

    "#{html}#{AttributionPolicy.payload(base_url: request.base_url)[:html]}"
  end
end
