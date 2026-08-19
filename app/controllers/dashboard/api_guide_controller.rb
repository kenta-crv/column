class Dashboard::ApiGuideController < ApplicationController
  before_action :authenticate_admin_or_client!
  layout "admin"

  def show
    @client = acting_as_admin? ? nil : current_client
  end
end
