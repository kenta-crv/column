class SitemapsController < ApplicationController
  def show
    CrawlableSitemap.ensure_fresh!
    send_file CrawlableSitemap::SITEMAP_PATH,
              type: "application/xml",
              disposition: "inline"
  end
end
