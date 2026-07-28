# frozen_string_literal: true

require "openssl"
require "resolv"
require "socket"
require "timeout"
require "uri"
require "whois"
require "whois-parser"

module SeoChecker
  # ドメイン年齢 / SSL証明書 / DNS(A・MX) を収集する。
  class TechnicalSignals
    TIMEOUT_SEC = 5

    class << self
      def collect(raw_url)
        host = extract_host(raw_url)
        return empty_result(error: I18n.t("drafity.seo_checker.tech_host_invalid")) if host.blank?

        {
          host: host,
          domain_age: fetch_domain_age(host),
          ssl: fetch_ssl(host),
          dns: fetch_dns(host)
        }
      end

      private

      def empty_result(error:)
        {
          host: nil,
          domain_age: { status: "error", message: error },
          ssl: { status: "error", message: error },
          dns: { status: "error", message: error, a_records: [], mx_records: [] }
        }
      end

      def extract_host(raw_url)
        text = raw_url.to_s.strip
        text = "https://#{text}" unless text.match?(/\Ahttps?:\/\//i)
        URI.parse(text).host.to_s.downcase.presence
      rescue URI::InvalidURIError
        nil
      end

      def registrable_domain(host)
        parts = host.to_s.split(".")
        return host if parts.size <= 2

        # 簡易: 末尾2ラベルを登録ドメインとみなす（co.jp 等は末尾3）
        if parts[-2].match?(/\A(co|or|ne|ac|go|ed|gr|lg)\z/i) && parts[-1].match?(/\Ajp\z/i)
          parts.last(3).join(".")
        else
          parts.last(2).join(".")
        end
      end

      def fetch_domain_age(host)
        domain = registrable_domain(host)
        record = Timeout.timeout(TIMEOUT_SEC) { Whois.whois(domain) }
        parser = record.parser
        created = parser.created_on rescue nil
        created ||= parse_created_from_raw(record.to_s)

        unless created
          return {
            status: "unknown",
            domain: domain,
            message: I18n.t("drafity.seo_checker.tech_domain_age_unknown")
          }
        end

        created_date = created.to_date
        days = (Time.zone.today - created_date).to_i
        years = (days / 365.25).floor
        months = ((days % 365.25) / 30.44).floor

        {
          status: "ok",
          domain: domain,
          created_on: created_date,
          age_days: days,
          age_years: years,
          age_months: months,
          message: I18n.t(
            "drafity.seo_checker.tech_domain_age_ok",
            years: years,
            months: months,
            date: created_date
          )
        }
      rescue Timeout::Error
        { status: "error", domain: registrable_domain(host), message: I18n.t("drafity.seo_checker.tech_timeout") }
      rescue StandardError => e
        Rails.logger.warn("[SeoChecker::TechnicalSignals] whois #{e.class}: #{e.message}")
        {
          status: "error",
          domain: registrable_domain(host),
          message: I18n.t("drafity.seo_checker.tech_domain_age_failed")
        }
      end

      def parse_created_from_raw(raw)
        patterns = [
          /Creation Date:\s*([^\r\n]+)/i,
          /Created On:\s*([^\r\n]+)/i,
          /Created:\s*([^\r\n]+)/i,
          /\[登録年月日\]\s*([^\r\n]+)/,
          /登録年月日\s*[:：]\s*([^\r\n]+)/
        ]
        patterns.each do |pat|
          match = raw.match(pat)
          next unless match

          begin
            return Time.zone.parse(match[1].to_s.strip)
          rescue ArgumentError, TypeError
            next
          end
        end
        nil
      end

      def fetch_ssl(host)
        Timeout.timeout(TIMEOUT_SEC) do
          tcp = TCPSocket.new(host, 443)
          begin
            ssl = OpenSSL::SSL::SSLSocket.new(tcp)
            ssl.hostname = host
            ssl.sync_close = true
            ssl.connect
            cert = ssl.peer_cert
            return {
              status: "error",
              message: I18n.t("drafity.seo_checker.tech_ssl_missing")
            } unless cert

            not_after = cert.not_after
            not_before = cert.not_before
            days_remaining = ((not_after.to_time - Time.now) / 86_400).floor
            valid_now = Time.now.between?(not_before, not_after)
            issuer = cert.issuer.to_a.find { |name, _, _| name == "O" }&.dig(1).presence ||
                     cert.issuer.to_s

            status =
              if !valid_now
                "error"
              elsif days_remaining < 30
                "warn"
              else
                "ok"
              end

            {
              status: status,
              valid: valid_now,
              not_before: not_before.to_date,
              not_after: not_after.to_date,
              days_remaining: days_remaining,
              issuer: issuer.to_s,
              message: I18n.t(
                "drafity.seo_checker.tech_ssl_#{status}",
                days: days_remaining,
                date: not_after.to_date,
                issuer: issuer.to_s.truncate(60)
              )
            }
          ensure
            tcp.close rescue nil
          end
        end
      rescue Timeout::Error
        { status: "error", message: I18n.t("drafity.seo_checker.tech_timeout") }
      rescue StandardError => e
        Rails.logger.warn("[SeoChecker::TechnicalSignals] ssl #{e.class}: #{e.message}")
        { status: "error", message: I18n.t("drafity.seo_checker.tech_ssl_failed") }
      end

      def fetch_dns(host)
        Timeout.timeout(TIMEOUT_SEC) do
          resolv = Resolv::DNS.new
          begin
            a_records = resolv.getresources(host, Resolv::DNS::Resource::IN::A).map { |r| r.address.to_s }
            mx_records = resolv.getresources(host, Resolv::DNS::Resource::IN::MX).filter_map do |r|
              exchange = r.exchange.to_s.chomp(".")
              next if exchange.blank?

              { preference: r.preference, exchange: exchange }
            end

            has_a = a_records.any?
            has_mx = mx_records.any?
            status =
              if has_a && has_mx
                "ok"
              elsif has_a
                "warn"
              else
                "error"
              end

            {
              status: status,
              a_records: a_records,
              mx_records: mx_records,
              has_a: has_a,
              has_mx: has_mx,
              message: I18n.t(
                "drafity.seo_checker.tech_dns_#{status}",
                a_count: a_records.size,
                mx_count: mx_records.size
              )
            }
          ensure
            resolv.close
          end
        end
      rescue Timeout::Error
        {
          status: "error",
          a_records: [],
          mx_records: [],
          message: I18n.t("drafity.seo_checker.tech_timeout")
        }
      rescue StandardError => e
        Rails.logger.warn("[SeoChecker::TechnicalSignals] dns #{e.class}: #{e.message}")
        {
          status: "error",
          a_records: [],
          mx_records: [],
          message: I18n.t("drafity.seo_checker.tech_dns_failed")
        }
      end
    end
  end
end
