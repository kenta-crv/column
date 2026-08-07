# frozen_string_literal: true

# 公開コラム記事下部（関連記事の直前）に出す自社サービスCTA。
# 優先順位: ServiceGenre.column_cta（ダッシュボード編集） → コード上のデフォルト CTAS
class ColumnServiceCta
  CTAS = {
    ai_sales_agent: {
      enabled: true,
      theme: "meetia",
      badge: "Meetia",
      title: "資料をアップロードするだけ。AIが24時間商談代行",
      lead: "営業担当の代わりにAIアバター「ミーティア」が即時商談。見込み度分析から自動追客まで一気通貫です。",
      cta_label: "無料で商談体験",
      path: "/"
    },
    app: {
      enabled: true,
      theme: "okurite",
      badge: "Okurite",
      title: "AI×プロで、営業成果を仕組み化する",
      lead: "フォーム営業・テレアポ・インサイドセールスまで。低コストで大量アプローチできる営業代行です。",
      cta_label: "Okuriteのサービスを見る",
      path: "/okurite"
    },
    cargo: {
      enabled: true,
      theme: "jwork",
      badge: "J Work",
      title: "Amazon配送の人材確保・業務請負はLINEで相談",
      lead: "ドライバー採用や業務請負について、まずはお気軽にご相談ください。",
      cta_label: "新規取引相談（LINE）",
      url: "https://lin.ee/NZBWRrsD",
      by_sub_genre: {
        driver_recruitment: {
          theme: "jwork-recruit",
          badge: "求職者向け",
          title: "Amazon配送ドライバーのお仕事はLINEで",
          lead: "未経験歓迎。お仕事情報をLINEで受け取れます。",
          cta_label: "お仕事の応募（LINE）",
          url: "https://lin.ee/8pGADE1"
        }
      }
    },
    vender: {
      enabled: true,
      theme: "vender",
      badge: "自販機ねっと",
      title: "自動販売機の設置・購入を無料相談",
      lead: "無料設置から本体購入まで。立地や運営方針に合わせた最適なプランをご提案します。",
      cta_label: "設置・購入について相談する",
      path: "/"
    },
    cleaning: {
      enabled: true,
      theme: "okwork",
      badge: "OK清掃",
      title: "日常清掃・オフィス清掃はOK清掃へ",
      lead: "20〜50代中心のスタッフ体制で、施設の美観と衛生を安定運用します。",
      cta_label: "清掃サービスを見る",
      path: "/"
    },
    housekeeping: {
      enabled: true,
      theme: "kurasera",
      badge: "クラセラ",
      title: "家事代行・ハウスクリーニングはクラセラ",
      lead: "掃除・洗濯・片付けなど、暮らしの家事負担をプロがサポートします。",
      cta_label: "クラセラのサービスを見る",
      path: "/"
    },
    ai_interview: {
      enabled: true,
      theme: "recrivo",
      badge: "Recrivo",
      title: "一次面接をAIが代行。採用スピードを上げる",
      lead: "求職者が好きな時間にAI面接を受診。評価結果を可視化し、面接工数を削減します。",
      cta_label: "Recrivoを見る",
      path: "/"
    },
    ai_article_generation: {
      enabled: true,
      theme: "drafity",
      badge: "Drafity",
      title: "SEO記事を、ピラー／クラスターで自動生成",
      lead: "検索需要に沿った高品質記事を短時間で生成。オウンドメディアの資産化を加速します。",
      cta_label: "Drafityを始める",
      path: "/"
    },
    ai_article: {
      enabled: true,
      theme: "drafity",
      badge: "Drafity",
      title: "AI記事生成でコンテンツSEOを加速",
      lead: "親記事・子記事の設計から生成まで。検索流入につながる記事運用を支援します。",
      cta_label: "サービスを見る",
      path: "/"
    },
    emergency_cleaning: {
      enabled: true,
      theme: "okwork",
      badge: "OK特殊クリーン",
      title: "特殊清掃・緊急対応のご相談",
      lead: "専門機材とプロの技術で、迅速かつ丁寧に対応します。",
      cta_label: "特殊清掃について相談する",
      path: "/"
    }
  }.freeze

  THEME_OPTIONS = [
    ["Meetia", "meetia"],
    ["Okurite", "okurite"],
    ["J Work", "jwork"],
    ["J Work（求職）", "jwork-recruit"],
    ["自販機ねっと", "vender"],
    ["OK清掃", "okwork"],
    ["クラセラ", "kurasera"],
    ["Recrivo", "recrivo"],
    ["Drafity", "drafity"],
    ["デフォルト", "default"]
  ].freeze

  def self.resolve(column)
    return nil if column.blank?

    key = GenreRegistry.canonical_key(column.genre)&.to_sym
    return nil if key.blank?

    base = stored_payload_for(column, key) || default_payload_for(key)
    return nil if base.blank?
    return nil if disabled?(base)

    sub_key = GenreRegistry.resolve_sub_category_key(column, key)
    override = dig_sub_genre(base, sub_key)
    merge_cta(base, override)
  end

  def self.default_payload_for(key)
    canon = GenreRegistry.canonical_key(key)&.to_sym
    return nil if canon.blank?

    CTAS[canon]&.deep_dup
  end

  def self.stringify_payload(payload)
    return {} if payload.blank?

    case payload
    when Hash
      payload.each_with_object({}) do |(k, v), result|
        result[k.to_s] = stringify_payload(v)
      end
    when Array
      payload.map { |item| stringify_payload(item) }
    else
      payload
    end
  end

  def self.symbolize_payload(payload)
    return {} if payload.blank?

    case payload
    when Hash
      payload.each_with_object({}) do |(k, v), result|
        result[k.to_sym] = symbolize_payload(v)
      end
    when Array
      payload.map { |item| symbolize_payload(item) }
    else
      payload
    end
  end

  def self.stored_payload_for(column, key)
    return nil unless ServiceGenre.table_exists?
    return nil unless ServiceGenre.column_names.include?("column_cta")

    keys = GenreRegistry.equivalent_keys(key)
    scope = ServiceGenre.where(key: keys)

    record = scope.find_by(client_id: column.client_id) if column.client_id.present?
    record ||= scope.find_by(client_id: nil)
    return nil if record.blank?

    raw = record.column_cta
    return nil if blank_payload?(raw)

    symbolize_payload(raw)
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    nil
  end

  def self.blank_payload?(payload)
    return true if payload.blank?

    data = payload.with_indifferent_access
    data[:title].blank? && data[:cta_label].blank? && data[:url].blank? && data[:path].blank? && data[:badge].blank?
  end

  def self.disabled?(payload)
    flag = payload.with_indifferent_access[:enabled]
    flag == false || flag.to_s == "false" || flag.to_s == "0"
  end

  def self.dig_sub_genre(base, sub_key)
    return nil if sub_key.blank?

    by_sub = base.with_indifferent_access[:by_sub_genre]
    return nil unless by_sub.is_a?(Hash)

    by_sub[sub_key.to_s].presence || by_sub[sub_key.to_sym].presence
  end

  def self.merge_cta(base, override)
    data = base.except(:by_sub_genre, "by_sub_genre")
    data = symbolize_payload(data)
    return data if override.blank?

    data.merge(symbolize_payload(override).except(:by_sub_genre))
  end
  private_class_method :merge_cta, :dig_sub_genre, :disabled?, :blank_payload?
end
