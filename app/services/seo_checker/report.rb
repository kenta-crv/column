# frozen_string_literal: true

module SeoChecker
  class Report
    Outcome = Struct.new(:ok, :report, :error, keyword_init: true)

    class << self
      def generate(raw_url, keyword: nil)
        fetch = SeoChecker::PageFetcher.fetch(raw_url)
        if fetch.error.present? || fetch.body.blank?
          return Outcome.new(ok: false, error: fetch.error.presence || I18n.t("drafity.seo_checker.error_fetch_failed"))
        end

        technical = SeoChecker::TechnicalSignals.collect(fetch.final_url.presence || fetch.url)
        analysis = SeoChecker::Analyzer.analyze(
          url: fetch.url,
          html: fetch.body,
          final_url: fetch.final_url,
          keyword: keyword,
          technical: technical
        )

        Outcome.new(ok: true, report: analysis)
      end
    end
  end
end
