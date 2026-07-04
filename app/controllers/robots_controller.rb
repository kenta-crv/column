class RobotsController < ApplicationController
  def show
    render plain: CrawlPolicy.robots_txt_body, content_type: "text/plain"
  end
end
