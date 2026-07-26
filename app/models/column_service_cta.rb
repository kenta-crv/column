# frozen_string_literal: true

# 公開コラム記事下部（関連記事の直前）に出す自社サービスCTA。
# ServiceGenre の DB 上書きとは独立して保持し、ジャンルごとに文言・導線を定義する。
class ColumnServiceCta
  CTAS = {
    meetia: {
      theme: "meetia",
      badge: "Meetia",
      title: "資料をアップロードするだけ。AIが24時間商談代行",
      lead: "営業担当の代わりにAIアバター「ミーティア」が即時商談。見込み度分析から自動追客まで一気通貫です。",
      cta_label: "無料で商談体験",
      path: "/"
    },
    app: {
      theme: "okurite",
      badge: "Okurite",
      title: "AI×プロで、営業成果を仕組み化する",
      lead: "フォーム営業・テレアポ・インサイドセールスまで。低コストで大量アプローチできる営業代行です。",
      cta_label: "Okuriteのサービスを見る",
      path: "/okurite"
    },
    cargo: {
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
      theme: "vender",
      badge: "自販機ねっと",
      title: "自動販売機の設置・購入を無料相談",
      lead: "無料設置から本体購入まで。立地や運営方針に合わせた最適なプランをご提案します。",
      cta_label: "設置・購入について相談する",
      path: "/"
    },
    cleaning: {
      theme: "okwork",
      badge: "OK清掃",
      title: "日常清掃・オフィス清掃はOK清掃へ",
      lead: "20〜50代中心のスタッフ体制で、施設の美観と衛生を安定運用します。",
      cta_label: "清掃サービスを見る",
      path: "/"
    },
    housekeeping: {
      theme: "kurasera",
      badge: "クラセラ",
      title: "家事代行・ハウスクリーニングはクラセラ",
      lead: "掃除・洗濯・片付けなど、暮らしの家事負担をプロがサポートします。",
      cta_label: "クラセラのサービスを見る",
      path: "/"
    },
    ai_interview: {
      theme: "recrivo",
      badge: "Recrivo",
      title: "一次面接をAIが代行。採用スピードを上げる",
      lead: "求職者が好きな時間にAI面接を受診。評価結果を可視化し、面接工数を削減します。",
      cta_label: "Recrivoを見る",
      path: "/"
    },
    ai_article_generation: {
      theme: "drafity",
      badge: "Drafity",
      title: "SEO記事を、ピラー／クラスターで自動生成",
      lead: "検索需要に沿った高品質記事を短時間で生成。オウンドメディアの資産化を加速します。",
      cta_label: "Drafityを始める",
      path: "/"
    },
    ai_article: {
      theme: "drafity",
      badge: "Drafity",
      title: "AI記事生成でコンテンツSEOを加速",
      lead: "親記事・子記事の設計から生成まで。検索流入につながる記事運用を支援します。",
      cta_label: "サービスを見る",
      path: "/"
    },
    emergency_cleaning: {
      theme: "okwork",
      badge: "OK特殊クリーン",
      title: "特殊清掃・緊急対応のご相談",
      lead: "専門機材とプロの技術で、迅速かつ丁寧に対応します。",
      cta_label: "特殊清掃について相談する",
      path: "/"
    }
  }.freeze

  def self.resolve(column)
    return nil if column.blank?

    key = GenreRegistry.canonical_key(column.genre)&.to_sym
    return nil if key.blank?

    base = CTAS[key]
    return nil if base.blank?

    sub_key = GenreRegistry.resolve_sub_category_key(column, key)
    override = base.dig(:by_sub_genre, sub_key&.to_sym)
    merge_cta(base, override)
  end

  def self.merge_cta(base, override)
    data = base.except(:by_sub_genre)
    return data if override.blank?

    data.merge(override.except(:by_sub_genre))
  end
  private_class_method :merge_cta
end
