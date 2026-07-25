# frozen_string_literal: true

module SeoChecker
  # IP 単位で 1 日あたりの診断回数を制限する。
  # Rails.cache が null_store でも動くよう、専用 FileStore を使う。
  class UsageLimiter
    DAILY_LIMIT = 3
    CACHE_DIR = Rails.root.join("tmp", "seo_checker_cache")

    class << self
      def remaining(ip)
        [DAILY_LIMIT - used(ip), 0].max
      end

      def used(ip)
        store.read(cache_key(ip)).to_i
      end

      def allowed?(ip)
        remaining(ip).positive?
      end

      def consume!(ip)
        key = cache_key(ip)
        count = store.increment(key, 1, expires_in: expires_in_seconds)
        # increment が未対応／初回 nil の環境向けフォールバック
        if count.nil?
          count = used(ip) + 1
          store.write(key, count, expires_in: expires_in_seconds)
        end
        count
      end

      def reset!(ip)
        store.delete(cache_key(ip))
      end

      private

      def store
        @store ||= begin
          FileUtils.mkdir_p(CACHE_DIR)
          ActiveSupport::Cache::FileStore.new(CACHE_DIR)
        end
      end

      def cache_key(ip)
        "seo_checker:usage:#{normalize_ip(ip)}:#{Time.zone.today}"
      end

      def normalize_ip(ip)
        ip.to_s.strip.presence || "unknown"
      end

      def expires_in_seconds
        (Time.zone.tomorrow.beginning_of_day - Time.zone.now).ceil
      end
    end
  end
end
