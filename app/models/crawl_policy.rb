module CrawlPolicy
  GENRE_KEY = "ai_article"
  OVERSEAS_SEO_GENRE_KEY = "overseas_seo"
  CRAWLABLE_GENRE_KEYS = [GENRE_KEY, OVERSEAS_SEO_GENRE_KEY].freeze
  TOPS_PATH = "/tops"
  SEO_CHECKER_PATH = "/tools/seo-checker"
  OVERSEAS_SEO_PATH = "/overseas"
  SITEMAP_HOST = ENV.fetch("SITEMAP_DEFAULT_HOST", "https://drafity.pro")

  module_function

  def crawlable_genre?(genre)
    CRAWLABLE_GENRE_KEYS.include?(GenreRegistry.resolve_key(genre).to_s)
  end

  def crawlable_genre_values
    CRAWLABLE_GENRE_KEYS.flat_map { |key| GenreRegistry.equivalent_keys(key) }
                        .map(&:to_s)
                        .uniq
                        .reject(&:blank?)
                        .select { |value| crawlable_genre?(value) }
  end

  STATIC_PATHS = [
    "/",
    SEO_CHECKER_PATH,
    OVERSEAS_SEO_PATH,
    "/en",
    "/en#{SEO_CHECKER_PATH}",
    "/#{GENRE_KEY}/columns",
    "/en/#{GENRE_KEY}/columns",
    "/#{OVERSEAS_SEO_GENRE_KEY}/columns"
  ].freeze

  def crawlable_columns
    Column.where(genre: crawlable_genre_values)
          .merge(Column.published)
          .merge(Column.with_generated_body)
          .where.not(code: [nil, ""])
  end

  def composition
    scope = crawlable_columns
    {
      static: STATIC_PATHS.size,
      articles: scope.count,
      total: STATIC_PATHS.size + scope.count,
      by_genre: scope.group(:genre).count,
      official: scope.where(client_id: nil).count,
      client_owned: scope.where.not(client_id: nil).count,
      values: crawlable_genre_values
    }
  end

  def column_path(column)
    raw_genre = column.respond_to?(:attributes) && column.attributes.key?("genre") ? column[:genre] : nil
    genre = GenreRegistry.resolve_key(raw_genre).to_s
    genre = GENRE_KEY unless crawlable_genre?(genre)
    slug = column.respond_to?(:public_code) ? column.public_code.presence : nil
    slug = column.code if slug.blank?
    path = "/#{genre}/columns/#{slug}"
    column.try(:english_article?) ? "/en#{path}" : path
  end

  def robots_txt_body
    # Allow を先に書き、同一 User-agent グループにまとめる。
    # Disallow: / だけでは /sitemap.xml まで塞がり、GSC がサイトマップを読めなくなる。
    <<~ROBOTS
      User-agent: *
      Allow: /$
      Allow: /sitemap.xml
      Allow: #{TOPS_PATH}$
      Allow: #{TOPS_PATH}/
      Allow: #{SEO_CHECKER_PATH}$
      Allow: #{SEO_CHECKER_PATH}/
      Allow: /en$
      Allow: /en/
      Allow: /en#{TOPS_PATH}$
      Allow: /en#{TOPS_PATH}/
      Allow: /en#{SEO_CHECKER_PATH}$
      Allow: /en#{SEO_CHECKER_PATH}/
      Allow: #{OVERSEAS_SEO_PATH}$
      Allow: #{OVERSEAS_SEO_PATH}/
      Allow: /#{OVERSEAS_SEO_GENRE_KEY}/columns
      Allow: /#{OVERSEAS_SEO_GENRE_KEY}/columns/
      Allow: /#{GENRE_KEY}/columns
      Allow: /#{GENRE_KEY}/columns/
      Allow: /en/#{GENRE_KEY}/columns
      Allow: /en/#{GENRE_KEY}/columns/
      Disallow: /

      Sitemap: #{SITEMAP_HOST}/sitemap.xml
    ROBOTS
  end
end


