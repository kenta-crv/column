# frozen_string_literal: true

class SeoCheckersController < ApplicationController
  helper_method :seo_checker_remaining, :seo_axis_label, :seo_checker_unlimited?

  def show
    @remaining = seo_checker_remaining
    @url = params[:url].to_s
    @keyword = params[:keyword].to_s
  end

  def create
    @remaining = seo_checker_remaining
    @url = params[:url].to_s.strip
    @keyword = params[:keyword].to_s.strip

    if @url.blank?
      flash.now[:alert] = t("drafity.seo_checker.alert_blank_url")
      return render :show, status: :unprocessable_entity
    end

    unless seo_checker_unlimited? || SeoChecker::UsageLimiter.allowed?(request.remote_ip)
      flash.now[:alert] = t("drafity.seo_checker.alert_limit", limit: SeoChecker::UsageLimiter::DAILY_LIMIT)
      @limit_reached = true
      return render :show, status: :too_many_requests
    end

    SeoChecker::UsageLimiter.consume!(request.remote_ip) unless seo_checker_unlimited?
    @remaining = seo_checker_remaining

    outcome = SeoChecker::Report.generate(@url, keyword: @keyword.presence)
    unless outcome.ok
      flash.now[:alert] = outcome.error
      return render :show, status: :unprocessable_entity
    end

    @report = outcome.report
    render :show
  end

  private

  def seo_checker_unlimited?
    admin_signed_in?
  end

  def seo_checker_remaining
    return Float::INFINITY if seo_checker_unlimited?

    SeoChecker::UsageLimiter.remaining(request.remote_ip)
  end

  def seo_axis_label(key)
    t("drafity.seo_checker.axis_#{key}", default: key.to_s)
  end
end
