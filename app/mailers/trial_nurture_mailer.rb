# frozen_string_literal: true

class TrialNurtureMailer < ApplicationMailer
  PRODUCT = "Drafity"
  OFFER_KINDS = %w[day11_conversion_offer day15_expired_followup].freeze

  default from: "info@j-work.jp"
  layout "mailer"

  def nurture(client:, kind:, progress:)
    @client = client
    @kind = kind.to_s
    @progress = progress
    @client_name = [@client.try(:name), @client.try(:company)].find(&:present?) || I18n.t("drafity.trial_nurture.customer_fallback")
    @trial_ends_at = @client.trial_ends_at
    @offer_expires_at = @progress&.conversion_offer_expires_at
    @show_offer = OFFER_KINDS.include?(@kind) && Subscription.trial_conversion_offer_configured?
    @percent_off = Subscription::STANDARD_INTRO_PERCENT_OFF
    @months = Subscription::STANDARD_INTRO_MONTHS
    @list_price = Subscription.price_for(:standard, currency: :jpy)
    @sale_price = Subscription.intro_price_for(:standard, currency: :jpy)
    @cta_url = cta_url_for(@kind)
    @cta_label = I18n.t("drafity.trial_nurture.kinds.#{@kind}.cta")
    @headline = I18n.t("drafity.trial_nurture.kinds.#{@kind}.headline")
    @body_lines = body_lines_for(@kind)

    mail(
      to: @client.email,
      subject: I18n.t(
        "drafity.trial_nurture.kinds.#{@kind}.subject",
        product: PRODUCT,
        percent: @percent_off
      )
    )
  end

  private

  def body_lines_for(kind)
    if OFFER_KINDS.include?(kind) && !@show_offer
      I18n.t("drafity.trial_nurture.kinds.#{kind}.body_without_offer")
    else
      I18n.t(
        "drafity.trial_nurture.kinds.#{kind}.body",
        percent: @percent_off,
        months: @months
      )
    end
  end

  def format_mail_date(value)
    return if value.blank?

    value.to_date.strftime("%Y年%m月%d日")
  end
  helper_method :format_mail_date

  def mailer_url_options
    {
      host: ActionMailer::Base.default_url_options[:host].presence || ENV.fetch("APP_HOST", "drafity.pro"),
      protocol: ActionMailer::Base.default_url_options[:protocol].presence || "https"
    }
  end

  def cta_url_for(kind)
    opts = mailer_url_options
    case kind
    when "day1_not_started", "day5_not_started"
      dashboard_service_genres_url(**opts)
    when "day5_no_pillar"
      dashboard_root_url(**opts)
    when "day5_no_child"
      dashboard_columns_url(scope: "pillar", **opts)
    when "day11_conversion_offer", "day15_expired_followup"
      checkout_confirmation_url(plan_type: "standard", **opts)
    else
      dashboard_root_url(**opts)
    end
  end
end
