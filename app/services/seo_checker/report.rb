# frozen_string_literal: true

module SeoChecker
  class Report
    Outcome = Struct.new(:ok, :report, :error, keyword_init: true)

    class << self
      def generate(raw_url)
        fetch = SeoChecker::PageFetcher.fetch(raw_url)
        if fetch.error.present? || fetch.body.blank?
          return Outcome.new(ok: false, error: fetch.error.presence || "ページを取得できませんでした")
        end

        analysis = SeoChecker::Analyzer.analyze(
          url: fetch.url,
          html: fetch.body,
          final_url: fetch.final_url
        )

        Outcome.new(ok: true, report: analysis)
      end
    end
  end
end
