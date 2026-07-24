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

  # Admin共有（client_id NULL）のジャンル・記事も他サイトEmbedから参照できるようにする。
  # 公開SSRと同様、Admin作成物を Client スコープで落とさない。
  def client_articles_scope
    Column.where(client_id: [@client.id, nil])
          .where.not(body: [nil, ""])
          .merge(Column.published)
          .where(genre: allowed_genre_values)
  end

  def allowed_genres_for_client
    @allowed_genres_for_client ||= ServiceGenre.where(client_id: [nil, @client.id]).order(:ja).to_a
  end

  def allowed_genre_values
    allowed_genres_for_client.flat_map { |genre| [genre.key, genre.ja] }.compact.uniq
  end

  def filter_genre_values
    matching_genre = allowed_genres_for_client.find do |genre|
      genre.key == params[:genre] || genre.ja == params[:genre]
    end

    matching_genre ? [matching_genre.key, matching_genre.ja].compact.uniq : [params[:genre]]
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
      published_at: column.published_at,
      created_at: column.created_at,
      updated_at: column.updated_at
    }
  end
end
