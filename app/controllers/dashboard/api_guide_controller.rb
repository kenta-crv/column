class Dashboard::ApiGuideController < ApplicationController
  before_action :authenticate_admin_or_client!
  layout "admin"

  def show
    @client = admin_signed_in? ? nil : current_client
  end
end
