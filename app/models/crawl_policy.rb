module CrawlPolicy
  GENRE_KEY = "ai_article"
  TOPS_PATH = "/tops"
  SITEMAP_HOST = ENV.fetch("SITEMAP_DEFAULT_HOST", "https://drafity.pro")

  module_function

  def crawlable_genre?(genre)
    GenreRegistry.resolve_key(genre).to_s == GENRE_KEY
  end

  def crawlable_columns
    Column.where(genre: GENRE_KEY).merge(Column.published).merge(Column.with_generated_body)
  end

  def column_path(column)
    "/#{GENRE_KEY}/columns/#{column.code}"
  end

  def robots_txt_body
    <<~ROBOTS
      User-agent: *
      Disallow: /

      User-agent: *
      Allow: #{TOPS_PATH}$
      Allow: #{TOPS_PATH}/
      Allow: /#{GENRE_KEY}/columns
      Allow: /#{GENRE_KEY}/columns/

      Sitemap: #{SITEMAP_HOST}/sitemap.xml
    ROBOTS
  end
end
