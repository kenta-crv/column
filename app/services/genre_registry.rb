module GenreRegistry
  GENRES = {
    cargo: {
      ja: "軽貨物",
      host: ["j-work.jp"],
      service_name: "OK配送",
      strong_points: "全国対応の軽貨物ネットワーク、企業・個人配送対応、ドライバーの迅速な確保。",
      keywords: ["軽貨物", "配送", "運送", "ドライバー", "宅配"],
      images: ['ser-cargo1.png','ser-cargo2.png','ser-cargo3.png','ser-cargo4.png']
    },

    cleaning: {
      ja: "清掃",
      host: ["okey.work"],
      service_name: "J Work",
      strong_points: "オフィス・店舗・常駐清掃に対応。徹底した品質管理と教育されたスタッフによる施工。",
      keywords: ["清掃", "クリーニング", "ハウスクリーニング", "ビル清掃"],
      images: ['cleaning1.jpg','cleaning2.jpg']
    },

    security: {
      ja: "警備",
      host: ["example-security.com"],
      service_name: "OK警備",
      strong_points: "常駐警備、出入管理、巡回警備、防災センター業務。有資格者による確実な監視と防犯体制。",
      keywords: ["警備", "セキュリティー", "施設警備", "交通整理"],
      images: ['security1.jpg', 'security2.jpg']
    },

    app: {
      ja: "営業代行",
      host: ["ri-plus.jp"],
      service_name: "Okurite",
      strong_points: "AIを活用した低価格かつ大量アプローチを叶えるトータル営業代行サービス",
      keywords: ["営業代行", "テレアポ", "インサイドセールス", "コールセンター"],
      images: ['app1.jpg','app2.jpg']
    },

    vender: {
      ja: "自販機",
      host: ["自販機.net"],
      service_name: "自動販売機の設置なら『自販機ねっと』",
      strong_points: "メーカー自販機一括見積及び自動販売機設置支援",
      keywords: ["自販機"],
      images: ['ads1.jpg','ads2.jpg']
    },

    pest: {
      ja: "害虫駆除",
      host: [],
      service_name: "シロアリ害虫駆除なら『シロアリ駆除士隊』",
      strong_points: "自宅のシロアリにお悩みの方に向けて害虫の駆除を行います。",
      keywords: ["シロアリ駆除", "トコジラミ駆除","ネズミ駆除"],
      images: []
    },

    construction: {
      ja: "建設",
      host: [],
      service_name: "OK建設",
      strong_points: "現場の人手不足解消、熟練工から手元作業員まで幅広くマッチング。",
      keywords: ["建設", "現場"],
      images: ['construction1.jpg','construction2.jpg']
    }
  }.freeze

  # reverse lookup
  def self.from_ja(ja)
    GENRES.find { |_, v| v[:ja] == ja }&.first&.to_s
  end

  def self.to_ja(key)
    GENRES[key.to_sym]&.dig(:ja)
  end

  def self.keywords(ja)
    GENRES[from_ja(ja)&.to_sym]&.dig(:keywords) || []
  end

  def self.service_profile(ja)
    g = GENRES[from_ja(ja)&.to_sym]
    return "各業界の専門知識に基づいた最適なソリューションを提供。" unless g

    <<~TEXT
      サービス名: #{g[:service_name]}
      強み: #{g[:strong_points]}
    TEXT
  end

  def self.images(key)
    GENRES[key.to_sym]&.dig(:images) || []
  end

  def self.allowed_hosts(host)
    GENRES.find { |_, v| v[:host].include?(host) }&.first
  end
end