# frozen_string_literal: true

class SeoCheckersController < ApplicationController
  AXIS_LABELS = {
    content: "コンテンツ量",
    basic_seo: "基本SEO",
    specificity: "内容の具体性",
    cluster: "クラスター性"
  }.freeze

  helper_method :seo_checker_remaining, :seo_axis_label

  def show
    @remaining = seo_checker_remaining
    @url = params[:url].to_s
  end

  def create
    @remaining = seo_checker_remaining
    @url = params[:url].to_s.strip

    if @url.blank?
      flash.now[:alert] = "URLを入力してください"
      return render :show, status: :unprocessable_entity
    end

    unless SeoChecker::UsageLimiter.allowed?(request.remote_ip)
      flash.now[:alert] = "本日の無料診断枠（#{SeoChecker::UsageLimiter::DAILY_LIMIT}回）を使い切りました。明日またお試しください。"
      @limit_reached = true
      return render :show, status: :too_many_requests
    end

    SeoChecker::UsageLimiter.consume!(request.remote_ip)
    @remaining = seo_checker_remaining

    outcome = SeoChecker::Report.generate(@url)
    unless outcome.ok
      flash.now[:alert] = outcome.error
      return render :show, status: :unprocessable_entity
    end

    @report = outcome.report
    render :show
  end

  private

  def seo_checker_remaining
    SeoChecker::UsageLimiter.remaining(request.remote_ip)
  end

  def seo_axis_label(key)
    AXIS_LABELS[key.to_sym] || key.to_s
  end
end
