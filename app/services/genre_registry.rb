module GenreRegistry
  GENRES = {
    cleaning: {
      ja: "清掃",
      host: ["okey.work"],
      service_name: "OK清掃",
      keywords: ["日常清掃", "清掃"],
      sub_categories: {
        daily_standard: {
          name: "日常清掃",
          target: "清掃美化を外注したい企業や施設",
          description: "週1回〜・1日3時間〜、決まった時間にスタッフが訪問する清掃サービス。トイレ掃除、ゴミ回収、床掃除など、建物の美観と衛生を維持する基本サービス。",
          features: ["週1回〜", "1回3時間〜の時間清掃", "清掃報告書発行", "深夜対応", "スタッフ固定制", "時間割引対応", "20〜50代中心"],
          keywords: ["日常清掃", "施設清掃"],
          price_hint: "時給3,000円〜 / 月額21,600円〜",
          area: "全国対応",
          strengths: "人材紹介業出身の清掃業である特性から、20〜50代の人材が中心。安定した清掃人材の提供が可能。",
          industry_weakness: "一般的に『人が足りない』『60〜80代中心』が日常清掃の最大課題ですが、OK清掃は若くて動ける人材が多いのが特徴です。"
        }
      }
    },

    app: {
      ja: "営業代行",
      host: ["ri-plus.jp"],
      service_name: "Okurite",
      strong_points: "AIを活用した低価格かつ大量アプローチを叶えるトータル営業代行サービス",
      keywords: ["営業代行", "テレアポ", "インサイドセールス", "コールセンター"],
      images: ['app1.jpg', 'app2.jpg']
    },

    housekeeping: {
      ja: "家事代行",
      host: ["kurasera.life"],
      service_name: "クラセラ",
      strong_points: "家事代行・お手伝いさん・家政婦・ハウスキーピングの依頼なら『クラセラ』",
      keywords: ["家事代行", "お手伝いさん", "家政婦", "ハウスキーピング"],
      images: ['app1.jpg', 'app2.jpg']
    },

    vender: {
      ja: "自販機",
      host: ["自販機.net"],
      service_name: "自動販売機の設置なら『自販機ねっと』",
      strong_points: "メーカー自販機一括見積及び自動販売機設置支援",
      keywords: ["自販機"],
      images: ['ads1.jpg', 'ads2.jpg']
    },

    pest: {
      ja: "害虫駆除",
      host: [],
      service_name: "シロアリ害虫駆除なら『シロアリ駆除士隊』",
      strong_points: "自宅のシロアリにお悩みの方に向けて害虫の駆除を行います。",
      keywords: ["シロアリ駆除", "トコジラミ駆除", "ネズミ駆除"],
      images: []
    }
  }.freeze

  # --- ヘルパーメソッド ---

  def self.from_ja(ja)
    GENRES.find { |_, v| v[:ja] == ja }&.first&.to_s
  end

  def self.to_ja(key)
    GENRES[key.to_sym]&.dig(:ja)
  end

  # AI生成用のプロフィール。中分類がある場合はそれを優先する
  def self.service_profile(category_key, sub_key = nil)
    g = GENRES[category_key.to_sym]
    return "専門知識に基づいた最適なソリューションを提供。" unless g

    if sub_key && g[:sub_categories] && g[:sub_categories][sub_key.to_sym]
      s = g[:sub_categories][sub_key.to_sym]
      return <<~TEXT
        サービス名: #{g[:service_name]}（#{s[:name]}）
        ターゲット: #{s[:target]}
        内容: #{s[:description]}
        特徴: #{s[:features].join('、')}
        料金: #{s[:price_hint]}
        強み: #{s[:strengths]}
        業界の課題と弊社の立ち位置: #{s[:industry_weakness]}
      TEXT
    end

    "サービス名: #{g[:service_name]}\n強み: #{g[:strong_points]}"
  end

  # 元々定義されていたメソッド（Controllerで使用するため必須）
  def self.allowed_hosts(host)
    GENRES.find { |_, v| v[:host].include?(host) }&.first
  end

  # 画像取得用
  def self.images(key)
    GENRES[key.to_sym]&.dig(:images) || []
  end

  # キーワード取得用
  def self.keywords(ja)
    GENRES[from_ja(ja)&.to_sym]&.dig(:keywords) || []
  end
end