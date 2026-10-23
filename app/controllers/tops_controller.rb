class TopsController < ApplicationController
  def index
  end

  def overseas_seo
    I18n.locale = :ja
  end

  def privacy
    @legal_page = :privacy
    render :legal
  end

  def tos
    @legal_page = :tos
    render :legal
  end

  def specific
    @legal_page = :specific
    render :legal
  end
end
