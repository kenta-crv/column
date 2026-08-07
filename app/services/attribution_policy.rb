# frozen_string_literal: true

# API / 埋め込み向けの明示アトリビューション判定。
# - trial / starter / standard: 必須
# - business / enterprise: なし
# - 自社ジャンル（ServiceGenre.client_id が nil）: Enterprise 扱い（なし）
class AttributionPolicy
  DEFAULT_URL = "https://drafity.pro"
  DEFAULT_TEXT = "Powered by Drafity"

  class << self
    def required?(client: nil, genre: nil, column: nil)
      return false if column.present? && column.client_id.nil?
      return false if platform_owned_genre?(genre, client: client)

      return true if client.nil?

      client.plan_limits.fetch(:attribution_required, true)
    end

    def payload(base_url: nil)
      url = attribution_url(base_url)
      text = I18n.t("drafity.attribution.text", default: DEFAULT_TEXT)
      {
        required: true,
        text: text,
        url: url,
        html: html_snippet(text: text, url: url)
      }
    end

    def html_snippet(text: nil, url: nil)
      label = text.presence || I18n.t("drafity.attribution.text", default: DEFAULT_TEXT)
      href = url.presence || attribution_url
      <<~HTML.squish
        <div class="drafity-attribution" style="margin-top:24px !important;padding-top:16px !important;border-top:1px solid rgba(0,0,0,0.08) !important;text-align:center !important;font-size:13px !important;line-height:1.5 !important;color:#6b7280 !important;">
          <a href="#{href}" target="_blank" rel="noopener noreferrer" style="color:#6b7280 !important;text-decoration:underline !important;">#{ERB::Util.html_escape(label)}</a>
        </div>
      HTML
    end

    def platform_owned_genre?(genre, client: nil)
      return false if genre.blank?

      keys = GenreRegistry.equivalent_keys(genre)
      ja = genre.to_s
      global = ServiceGenre.where(client_id: nil).where(key: keys).or(
        ServiceGenre.where(client_id: nil).where(ja: ja)
      ).exists?
      return false unless global

      # 顧客が同名の ServiceGenre を持つ場合はプラン判定に委ねる（自社免除にしない）
      return true if client.nil?

      !client.service_genres.where(key: keys).or(client.service_genres.where(ja: ja)).exists?
    end

    private

    def attribution_url(base_url = nil)
      configured = ENV["DRAFITY_ATTRIBUTION_URL"].presence
      return configured if configured.present?

      host = ENV.fetch("RAILS_ALLOWED_HOST", nil).presence
      return "https://#{host}" if host.present?

      base_url.presence || DEFAULT_URL
    end
  end
end
