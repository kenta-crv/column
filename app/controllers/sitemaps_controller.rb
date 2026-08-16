class SitemapsController < ApplicationController
  def show
    CrawlableSitemap.ensure_fresh!
    unless CrawlableSitemap::SITEMAP_PATH.exist?
      head :service_unavailable
      return
    end

    send_file CrawlableSitemap::SITEMAP_PATH,
              type: "application/xml",
              disposition: "inline"
  end
end
