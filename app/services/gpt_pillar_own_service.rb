# frozen_string_literal: true

# Note / Qiita / Zenn 向け生成器が、column.own_service_key に応じて
# 言及する自社サービス名・URL を切り替えるための共通モジュール。
module GptPillarOwnService
  extend ActiveSupport::Concern

  OWN_SERVICES = {
    "meetia" => { name: "Meetia", url: "https://meetia.pro" },
    "recrivo" => { name: "Recrivo", url: "https://recrivo.pro" },
    "okurite" => { name: "Okurite", url: "https://okurite.pro" },
    "drafity" => { name: "Drafity", url: "https://drafity.pro" }
  }.freeze

  DEFAULT_OWN_SERVICE_KEY = "drafity"

  class_methods do
    def with_own_service_for(column)
      Thread.current[:gpt_pillar_own_service_key] = resolve_own_service_key(column)
      yield
    ensure
      Thread.current[:gpt_pillar_own_service_key] = nil
    end

    def own_service_name
      own_service_config[:name]
    end

    def own_service_url
      own_service_config[:url]
    end

    def resolve_own_service_key(column)
      key = column.try(:own_service_key).to_s.presence
      return key if key.present? && OWN_SERVICES.key?(key)

      DEFAULT_OWN_SERVICE_KEY
    end

    def own_service_config
      key = Thread.current[:gpt_pillar_own_service_key].presence || DEFAULT_OWN_SERVICE_KEY
      OWN_SERVICES.fetch(key, OWN_SERVICES.fetch(DEFAULT_OWN_SERVICE_KEY))
    end
  end
end
