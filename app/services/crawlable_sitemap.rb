require "sitemap_generator"

class CrawlableSitemap
  SITEMAP_PATH = Rails.root.join("public", "sitemap.xml")

  def self.refresh!
    SitemapGenerator::Sitemap.default_host = CrawlPolicy::SITEMAP_HOST
    SitemapGenerator::Sitemap.compress = false
    SitemapGenerator::Sitemap.public_path = Rails.public_path.to_s
    SitemapGenerator::Sitemap.sitemaps_path = ""
    SitemapGenerator::Sitemap.include_root = false
    SitemapGenerator::Sitemap.include_index = false
    SitemapGenerator::Sitemap.search_engines.clear

    SitemapGenerator::Sitemap.create(filename: "sitemap") do
      add "/", changefreq: "weekly", priority: 1.0
      add CrawlPolicy::TOPS_PATH, changefreq: "weekly", priority: 1.0
      add "/#{CrawlPolicy::GENRE_KEY}/columns", changefreq: "daily", priority: 0.9

      CrawlPolicy.crawlable_columns.find_each do |column|
        add CrawlPolicy.column_path(column),
            lastmod: column.updated_at,
            changefreq: "weekly",
            priority: 0.8
      end
    end
  end

  def self.ensure_fresh!(max_age: 1.hour)
    refresh! unless SITEMAP_PATH.exist? && SITEMAP_PATH.mtime > max_age.ago
  end
end
