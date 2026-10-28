require "sitemap_generator"

class CrawlableSitemap
  # nginx は public/ の同名ファイルを Rails より先に返す。
  # 生成物を public に置くと、古い2URLのまま更新されなくなる。
  SITEMAP_DIR = Rails.root.join("tmp", "sitemaps")
  SITEMAP_PATH = SITEMAP_DIR.join("sitemap.xml")

  def self.refresh!
    if Rails.env.development?
      raise "サイトマップは RAILS_ENV=production で生成してください。development の SQLite で作ると件数がずれます。"
    end

    composition = CrawlPolicy.composition
    message = "[CrawlableSitemap] static=#{composition[:static]} articles=#{composition[:articles]} total=#{composition[:total]} by_genre=#{composition[:by_genre]} official=#{composition[:official]} client_owned=#{composition[:client_owned]} values=#{composition[:values]}"
    puts message
    Rails.logger.info(message)

    FileUtils.mkdir_p(SITEMAP_DIR)

    SitemapGenerator::Sitemap.default_host = CrawlPolicy::SITEMAP_HOST
    SitemapGenerator::Sitemap.compress = false
    SitemapGenerator::Sitemap.public_path = SITEMAP_DIR.to_s
    SitemapGenerator::Sitemap.sitemaps_path = ""
    SitemapGenerator::Sitemap.include_root = false
    SitemapGenerator::Sitemap.include_index = false
    SitemapGenerator::Sitemap.search_engines.clear

    ja_article_lastmod = listing_lastmod(CrawlPolicy::GENRE_KEY, "ja")
    en_article_lastmod = listing_lastmod(CrawlPolicy::GENRE_KEY, "en")
    overseas_lastmod = listing_lastmod(CrawlPolicy::OVERSEAS_SEO_GENRE_KEY, "ja")

    SitemapGenerator::Sitemap.create(filename: "sitemap") do
      # 固定ページの変更日は記録していない。生成日は入れない。
      add "/", changefreq: "weekly", priority: 1.0, lastmod: nil
      add CrawlPolicy::SEO_CHECKER_PATH, changefreq: "weekly", priority: 0.8, lastmod: nil
      add CrawlPolicy::OVERSEAS_SEO_PATH, changefreq: "weekly", priority: 0.9, lastmod: nil
      add "/en", changefreq: "weekly", priority: 0.9, lastmod: nil
      add "/en#{CrawlPolicy::SEO_CHECKER_PATH}", changefreq: "weekly", priority: 0.7, lastmod: nil
      add "/#{CrawlPolicy::GENRE_KEY}/columns", changefreq: "daily", priority: 0.9, lastmod: ja_article_lastmod
      add "/en/#{CrawlPolicy::GENRE_KEY}/columns", changefreq: "daily", priority: 0.8, lastmod: en_article_lastmod
      add "/#{CrawlPolicy::OVERSEAS_SEO_GENRE_KEY}/columns", changefreq: "daily", priority: 0.9, lastmod: overseas_lastmod

      CrawlPolicy.crawlable_columns.find_each do |column|
        add CrawlPolicy.column_path(column),
            lastmod: column.content_updated_at,
            changefreq: "weekly",
            priority: 0.8
      end
    end
  end

  def self.listing_lastmod(genre_key, language)
    genres = GenreRegistry.equivalent_keys(genre_key).map(&:to_s).reject(&:blank?)
    return nil if genres.empty?

    CrawlPolicy.crawlable_columns
               .merge(Column.for_language(language))
               .where(genre: genres)
               .maximum(:content_updated_at)
  end

  def self.ensure_fresh!(max_age: 1.hour)
    return if SITEMAP_PATH.exist? && SITEMAP_PATH.mtime > max_age.ago

    refresh!
  rescue StandardError => e
    Rails.logger.error("[CrawlableSitemap] refresh failed: #{e.class}: #{e.message}")
    raise unless SITEMAP_PATH.exist?
  end
end
