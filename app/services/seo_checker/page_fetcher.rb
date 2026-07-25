# frozen_string_literal: true

require "net/http"
require "ipaddr"
require "resolv"

module SeoChecker
  class PageFetcher
    Result = Struct.new(:url, :final_url, :body, :status, :error, keyword_init: true)

    MAX_REDIRECTS = 3
    MAX_BODY_BYTES = 2_000_000
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10
    USER_AGENT = "DrafitySeoChecker/1.0 (+https://drafity.pro/tools/seo-checker)"

    BLOCKED_NETWORKS = [
      IPAddr.new("0.0.0.0/8"),
      IPAddr.new("10.0.0.0/8"),
      IPAddr.new("127.0.0.0/8"),
      IPAddr.new("169.254.0.0/16"),
      IPAddr.new("172.16.0.0/12"),
      IPAddr.new("192.168.0.0/16"),
      IPAddr.new("::1/128"),
      IPAddr.new("fc00::/7"),
      IPAddr.new("fe80::/10")
    ].freeze

    class << self
      def fetch(raw_url)
        uri = normalize_uri(raw_url)
        return Result.new(url: raw_url, error: t_seo("error_invalid_url")) unless uri

        current = uri
        redirects = 0

        loop do
          guard_error = ssrf_guard(current)
          return Result.new(url: raw_url, final_url: current.to_s, error: guard_error) if guard_error

          response = http_get(current)

          case response
          when Net::HTTPRedirection
            location = response["location"].to_s
            return Result.new(url: raw_url, final_url: current.to_s, error: t_seo("error_bad_redirect")) if location.blank?

            redirects += 1
            return Result.new(url: raw_url, final_url: current.to_s, error: t_seo("error_too_many_redirects")) if redirects > MAX_REDIRECTS

            current = current.merge(location)
            next
          when Net::HTTPSuccess
            body = response.body.to_s
            if body.bytesize > MAX_BODY_BYTES
              return Result.new(url: raw_url, final_url: current.to_s, error: t_seo("error_body_too_large"))
            end

            body = body.dup.force_encoding("UTF-8")
            body = body.encode("UTF-8", invalid: :replace, undef: :replace) unless body.valid_encoding?

            return Result.new(
              url: raw_url,
              final_url: current.to_s,
              body: body,
              status: response.code.to_i
            )
          else
            code = response.respond_to?(:code) ? response.code : "?"
            return Result.new(url: raw_url, final_url: current.to_s, error: t_seo("error_http", code: code))
          end
        end
      rescue StandardError => e
        Rails.logger.warn("[SeoChecker::PageFetcher] #{e.class}: #{e.message}")
        Result.new(url: raw_url, error: t_seo("error_fetch_failed"))
      end

      private

      def t_seo(key, **opts)
        I18n.t("drafity.seo_checker.#{key}", **opts)
      end

      def normalize_uri(raw_url)
        text = raw_url.to_s.strip
        text = "https://#{text}" unless text.match?(/\Ahttps?:\/\//i)
        uri = URI.parse(text)
        return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        return nil if uri.host.blank?

        uri
      rescue URI::InvalidURIError
        nil
      end

      def ssrf_guard(uri)
        return t_seo("error_scheme") unless %w[http https].include?(uri.scheme)
        return t_seo("error_host") if uri.host.blank?

        default_port = uri.scheme == "https" ? 443 : 80
        return t_seo("error_port") unless uri.port == default_port

        host = uri.host
        return t_seo("error_private") if %w[localhost metadata].include?(host.downcase)

        addresses = Resolv.getaddresses(host)
        return t_seo("error_resolve") if addresses.empty?

        addresses.each do |addr|
          ip = IPAddr.new(addr)
          return t_seo("error_private") if BLOCKED_NETWORKS.any? { |net| net.include?(ip) }
        end

        nil
      rescue Resolv::ResolvError, IPAddr::InvalidAddressError
        t_seo("error_resolve")
      end

      def http_get(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        http.write_timeout = OPEN_TIMEOUT if http.respond_to?(:write_timeout=)

        request = Net::HTTP::Get.new(uri.request_uri.presence || "/")
        request["User-Agent"] = USER_AGENT
        request["Accept"] = "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8"
        request["Accept-Language"] = "ja,en;q=0.8"

        http.request(request)
      end
    end
  end
end
