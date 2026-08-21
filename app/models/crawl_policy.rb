module CrawlPolicy
  GENRE_KEY = "ai_article"
  TOPS_PATH = "/tops"
  SEO_CHECKER_PATH = "/tools/seo-checker"
  SITEMAP_HOST = ENV.fetch("SITEMAP_DEFAULT_HOST", "https://drafity.pro")

  module_function

  def crawlable_genre?(genre)
    GenreRegistry.resolve_key(genre).to_s == GENRE_KEY
  end

  def crawlable_genre_values
    GenreRegistry.equivalent_keys(GENRE_KEY).map(&:to_s).uniq.reject(&:blank?).select { |value| crawlable_genre?(value) }
  end

  STATIC_PATHS = [
    "/",
    "/plans",
    TOPS_PATH,
    SEO_CHECKER_PATH,
    "/en",
    "/en/plans",
    "/en#{TOPS_PATH}",
    "/en#{SEO_CHECKER_PATH}",
    "/#{GENRE_KEY}/columns",
    "/en/#{GENRE_KEY}/columns"
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
    path = "/#{GENRE_KEY}/columns/#{column.code}"
    column.try(:english_article?) ? "/en#{path}" : path
  end

  def robots_txt_body
    # Allow を先に書き、同一 User-agent グループにまとめる。
    # Disallow: / だけでは /sitemap.xml まで塞がり、GSC がサイトマップを読めなくなる。
    <<~ROBOTS
      User-agent: *
      Allow: /$
      Allow: /sitemap.xml
      Allow: /plans$
      Allow: /plans/
      Allow: #{TOPS_PATH}$
      Allow: #{TOPS_PATH}/
      Allow: #{SEO_CHECKER_PATH}$
      Allow: #{SEO_CHECKER_PATH}/
      Allow: /en$
      Allow: /en/
      Allow: /en/plans$
      Allow: /en/plans/
      Allow: /en#{TOPS_PATH}$
      Allow: /en#{TOPS_PATH}/
      Allow: /en#{SEO_CHECKER_PATH}$
      Allow: /en#{SEO_CHECKER_PATH}/
      Allow: /#{GENRE_KEY}/columns
      Allow: /#{GENRE_KEY}/columns/
      Allow: /en/#{GENRE_KEY}/columns
      Allow: /en/#{GENRE_KEY}/columns/
      Disallow: /

      Sitemap: #{SITEMAP_HOST}/sitemap.xml
    ROBOTS
  end
end


