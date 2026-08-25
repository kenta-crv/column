require "set"

module GenreRegistry
  FALLBACK_GENRES = {
    cleaning: {
      ja: "清掃",
      en: "Cleaning",
      host: ["okey.work"],
      service_name: "OK清掃",
      columns_index_description: "OK清掃の日常・施設清掃、巡回、定期、原状回復、特殊清掃に関する解説記事一覧。導入の進め方、運用ポイント、現場の事例をまとめています。",
      keywords: ["日常清掃", "施設清掃", "巡回清掃", "定期清掃", "原状回復", "特殊清掃"],
      sub_categories: {
        daily_standard: {
          name: "日常・施設清掃",
          name_en: "Routine & facility cleaning",
          target: "オフィス、店舗、学校、医療・介護、工場など、決まった時間の清掃を外注したい企業・施設",
          description: "週1回〜、決まった時間にスタッフが訪問する定常清掃。トイレ、ゴミ回収、床など建物の美観と衛生を維持する。業態（オフィス、学校、飲食、医療など）の差は記事テーマで持つ。",
          features: ["週1回〜", "1回3時間〜の時間清掃", "清掃報告書発行", "深夜・早朝対応", "スタッフ固定制", "20〜50代中心"],
          keywords: ["日常清掃", "施設清掃", "オフィス清掃", "学校清掃", "店舗清掃", "病院清掃", "工場清掃", "飲食店清掃"],
          price_hint: "時給3,000円〜 / 月額21,600円〜",
          area: "全国対応",
          strengths: "人材紹介業出身のため20〜50代が中心。業態が違っても、定常の訪問清掃として同じ運用で回せる。",
          industry_weakness: "一般的に『人が足りない』『高齢スタッフ中心』が課題だが、OK清掃は動ける人材を安定投入できる。"
        },
        apartment: {
          name: "巡回清掃",
          name_en: "Patrol cleaning",
          target: "不動産管理会社、物件オーナー、雑居ビル・マンションの大家",
          description: "週1回や月2回など決まった頻度で共用部を巡回。エントランス、廊下、階段、ゴミ置き場、ビル共用部の維持。",
          features: ["写真付き報告書", "簡易点検（電球切れ等）", "ゴミ置き場清掃", "複数物件一括対応"],
          keywords: ["マンション巡回清掃", "アパート清掃", "共用部掃除", "ビル巡回清掃", "雑居ビル掃除"],
          price_hint: "1棟あたり 月額数千円〜（棟数・階数による）",
          area: "全国対応",
          strengths: "写真報告が標準のため、遠方のオーナーでも共用部の状態が分かる。"
        },
        periodic: {
          name: "定期清掃",
          name_en: "Periodic cleaning (floors, glass)",
          target: "日常では落とせない床・ガラス汚れの発注者（オフィス、店舗、ビル、施設）",
          description: "数ヶ月に1回、専用機械（ポリッシャー、高圧洗浄）で洗浄。床ワックス、高所ガラス、カーペット。",
          features: ["床ポリッシャー洗浄", "ワックス塗布", "高所ガラス清掃", "カーペット洗浄"],
          keywords: ["定期清掃", "床ワックスがけ", "ガラス清掃", "高圧洗浄"],
          price_hint: "1回あたり要見積もり（平米数による単価設定）",
          area: "全国対応"
        },
        turnover: {
          name: "原状回復",
          name_en: "Restoration & vacancy cleaning",
          target: "賃貸物件の大家・管理会社",
          description: "退去後の空室クリーニング。必要に応じてクロス張り替えや小修繕まで。",
          features: ["空室全体清掃", "クロス・床張り替え", "水回り徹底洗浄", "パッキン交換等小修繕"],
          keywords: ["原状回復清掃", "退去後クリーニング", "空室清掃", "クロス張り替え"],
          price_hint: "間取り（1K・2LDK等）に応じた定額制あり",
          area: "全国対応",
          strengths: "清掃と内装を一括で引き受け、空室期間を短くする。"
        },
        special: {
          name: "特殊清掃",
          name_en: "Specialized cleaning",
          target: "物件オーナー、遺族、管理会社",
          description: "孤独死・事件現場の特殊清掃、遺品整理、ゴミ屋敷。通常清掃ではできない体液除去、害虫、オゾン消臭。",
          features: ["24時間緊急対応", "完全消臭（オゾン燻蒸）", "遺品整理・不用品回収", "除菌・消毒徹底"],
          keywords: ["特殊清掃", "孤独死清掃", "遺品整理", "ゴミ屋敷片付け", "オゾン消臭"],
          price_hint: "状況により要見積り（緊急対応可）",
          area: "全国対応",
          strengths: "専用薬剤と高濃度オゾンで臭いを元から断つ。近隣への配慮も含めて対応する。"
        }
      }
    },
    housekeeping: {
      ja: "家事代行",
      en: "Housekeeping",
      host: ["kurasera.life"],
      service_name: "クラセラ",
      columns_index_description: "クラセラの家事代行、シッター、高齢者の生活補助に関する解説記事一覧。依頼の流れ、料金の考え方、活用事例をまとめています。",
      keywords: ["家事代行", "ハウスキーピング", "お手伝いさん", "ベビーシッター", "キッズシッター", "英語シッター", "高齢者補助"],
      strong_points: "家事代行・シッター・高齢者の生活補助（介護領域外）の依頼なら『クラセラ』",
      sub_categories: {
        kaji_daiko: {
          name: "家事代行",
          name_en: "Household chore service",
          target: "掃除・洗濯・片付け・買い物など、家事を時間単位で外注したい個人・家庭",
          description: "家庭に入って家事を代行する。ハウスキーピング・お手伝いさんと呼ばれる依頼も含む。",
          features: ["掃除", "洗濯", "片付け", "買い物代行", "柔軟な時間設定"],
          keywords: ["家事代行", "ハウスキーピング", "お手伝いさん", "家政婦"],
          price_hint: "1時間3000円〜",
          area: "全国対応",
          strengths: "必要な家事だけを、家庭のやり方に合わせて依頼できる。"
        },
        babysitter: {
          name: "ベビーシッター",
          name_en: "Babysitter",
          target: "乳幼児の見守りを家庭で任せたい保護者",
          description: "乳幼児の世話と見守り。保育園の代替ではなく、指定場所での預かり。",
          features: ["乳幼児の見守り", "食事・おむつなどの日常世話", "保護者の外出中対応"],
          keywords: ["ベビーシッター", "乳児 預かり"],
          price_hint: "1時間3000円〜",
          area: "全国対応",
          strengths: "家庭のリズムに合わせて、短時間から預かりを依頼できる。"
        },
        kids_sitter: {
          name: "キッズシッター",
          name_en: "Kids sitter",
          target: "小学生前後の送迎・宿題・遊びの見守りを任せたい家庭",
          description: "自分で動ける子どもの見守り。放課後や習い事の前後に使う。",
          features: ["放課後の見守り", "宿題の付き添い", "習い事の送迎サポート"],
          keywords: ["キッズシッター", "小学生 シッター"],
          price_hint: "1時間3000円〜",
          area: "全国対応",
          strengths: "放課後の空白時間を、決まった人に任せられる。"
        },
        english_sitter: {
          name: "英語シッター",
          name_en: "English-speaking sitter",
          target: "英語環境での見守りや遊びを任せたい家庭",
          description: "英語で子どもと過ごすシッター。家庭内の見守り・遊びが中心。",
          features: ["英語でのコミュニケーション", "遊び・見守り", "家庭への訪問"],
          keywords: ["英語シッター", "バイリンガルシッター"],
          price_hint: "1時間3000円〜",
          area: "全国対応",
          strengths: "見守りと、暮らしの中で英語に触れる時間をセットにできる。"
        },
        senior_assist: {
          name: "高齢者補助",
          name_en: "Senior living support (non-care)",
          target: "介護保険ではない、生活の手伝いを求める本人・家族",
          description: "買い物同行、話し相手、軽い家事、通院の付き添い。入浴介助・医療行為・訪問介護は対象外。",
          features: ["買い物同行", "話し相手", "軽い家事", "通院の付き添い"],
          keywords: ["高齢者補助", "高齢者 生活支援"],
          price_hint: "1時間3000円〜",
          area: "全国対応",
          strengths: "介護の枠に入らない暮らしの手伝いとして依頼できる。",
          industry_weakness: "介護・医療行為は行わない。要介護や医療が主目的の依頼は専門機関へつなぐ。"
        }
      }
    },
    pest: {
      ja: "シロアリ駆除",
      en: "Termite control",
      host: [],
      service_name: "シロアリ害虫駆除なら『シロアリ駆除士隊』",
      columns_index_description: "シロアリ駆除・害虫対策に関する解説記事一覧。調査から施工、再発防止までのポイントをまとめています。",
      keywords: ["シロアリ駆除"],
      strong_points: "自宅のシロアリにお悩みの方に向けて害虫の駆除を行います。",
      sub_categories: {
        termite_control: {
          name: "シロアリ駆除",
          name_en: "Termite control",
          target: "住宅・建物のシロアリ被害に悩む個人",
          description: "建物内部に侵入したシロアリの駆除および再発防止処理を実施。",
          features: ["現地調査", "薬剤処理", "再発防止施工", "床下対応"],
          keywords: ["シロアリ駆除", "害虫駆除", "住宅メンテナンス"],
          price_hint: "要お見積り",
          area: "全国対応",
          strengths: "再発防止まで含めた施工設計により長期的な安全性を確保します。"
        }
      }
    },
    cargo: {
      ja: "外国人",
      en: "Foreign talent",
      host: ["okey.work"],
      service_name: "J Work",
      columns_index_description: "J Workの外国人向け解説記事一覧。雇用・特定技能、生活実務、求職、Amazon配送、相談窓口までをまとめています。",
      strong_points: "登録3,000人・毎月約500人増の外国人材基盤。企業の採用と、外国人本人の仕事探しの両方に対応。",
      keywords: ["外国人雇用", "外国人材", "特定技能", "永住ビザ", "Amazon配送", "外国人求人"],
      images: ["stock/cargo.jpg"],
      sub_categories: {
        delivery_partner: {
          name: "Amazon外国人配送",
          name_en: "Amazon delivery with foreign drivers",
          target: "Amazon配送を受託し、外国人ドライバーの確保・定着に課題がある企業",
          description: "Amazon配送に特化した外国人材の供給と業務請負。全国で稼働できる外国人ドライバーを手配します。",
          features: ["全国対応", "外国人配送ドライバー", "永住・就労可能な人材", "請負対応"],
          keywords: ["Amazon配送", "ドライバー採用", "Amazon配送業務請負", "外国人ドライバー確保", "Amazon DSP"],
          price_hint: "御社の単価そのままで業務請負 / 人材紹介可",
          area: "関東・関西・名古屋中心に全国でドライバー人材を手配可能",
          strengths: "人材紹介のノウハウを活かし、毎月500名規模の日本語が話せる永住ビザ人材からドライバー応募を得ています。体力のある20〜50代を優先確保し、定着率の高さが強みです。",
          industry_weakness: "軽貨物は高齢化と慢性的な人手不足が深刻です。J Workは独自集客で稼働人数を最大化しています。"
        },
        foreign_hiring: {
          name: "外国人雇用",
          name_en: "Hiring foreign talent",
          target: "外国人材の採用・受け入れを検討している企業の人事・現場責任者",
          description: "業界を問わず、外国人雇用の実務（在留資格、助成金、受け入れ体制、求人の出し方）を解説し、紹介・請負につなげます。",
          features: ["永住・定住層の紹介", "助成金の整理", "求人無料掲載の導線", "受け入れ体制の解説"],
          keywords: ["外国人雇用", "助成金", "受け入れ体制", "外国人材紹介"],
          price_hint: "求人掲載は無料から。会いたい人材は有料解除",
          area: "全国対応",
          strengths: "登録3,000人・月約500人増。条件に合う人数を先に見せ、必要な人だけつなぎます。",
          industry_weakness: "外国人雇用は制度情報が分散し、悪質な紹介も多い。一次情報と実在庫をセットで出します。"
        },
        driver_recruitment: {
          name: "外国人採用求職者",
          name_en: "Jobs for foreign residents",
          target: "日本で働きたい外国人、すでに在留している求職者",
          description: "日本での仕事の探し方、履歴書、就労できるビザ、Amazon配送を含む現場求人まで、本人向けに案内します。",
          features: ["未経験歓迎の求人", "LINEで応募", "車両貸出のある配送求人", "就労可能な求人の案内"],
          keywords: ["外国人求人", "外国人 仕事", "就労ビザ 仕事", "Amazonドライバー求人", "履歴書 外国人"],
          price_hint: "求職者の利用は無料",
          area: "関東・関西・愛知中心に全国対応",
          strengths: "日本語が話せる永住・就労可能な求人が中心。配送に限らず、仕事情報を本人に届けます。",
          industry_weakness: "求人詐欺や不明瞭な条件が多い中、実在の求人と相談窓口へつなぎます。"
        },
        life_guide: {
          name: "生活実務",
          name_en: "Life admin in Japan",
          target: "来日直後〜在留中の外国人。住民登録や保険など、生活の手続きで困っている人",
          description: "住民登録、マイナンバー、健康保険・年金、銀行口座、携帯電話、賃貸（保証人不要の探し方）など、来日後すぐ必要になる一次情報を本人向けに整理します。",
          features: ["来日後の手続き順", "役所・窓口の行き方", "必要書類のチェックリスト", "やさしい日本語での解説"],
          keywords: ["住民登録", "マイナンバー", "国民健康保険", "銀行口座 外国人", "携帯電話 契約", "賃貸 保証人不要"],
          price_hint: "情報の閲覧は無料",
          area: "日本全国（市区町村で手続きは異なる旨を注記）",
          strengths: "仕事探しと同じ導線で、生活の困りごとから登録・相談につなげられます。",
          industry_weakness: "制度は改正が多く誤情報も流通する。最新は自治体・公的サイトの確認を促し、J Workは案内に留めます。"
        },
        specified_skills: {
          name: "特定技能・技能実習",
          name_en: "Specified skilled & technical intern",
          target: "特定技能・技能実習での受け入れを検討する企業、登録支援機関、監理団体",
          description: "特定技能と技能実習の制度概要、受け入れ機関の役割、登録支援機関業務、申請の流れを企業向けに整理します。個別の許認可代行ではなく、判断材料と相談導線を提供します。",
          features: ["制度の違いの整理", "受け入れ企業の義務", "登録支援機関との役割分担", "公的情報への案内"],
          keywords: ["特定技能", "技能実習", "登録支援機関", "受け入れ機関", "在留資格 特定技能"],
          price_hint: "情報は無料。人材紹介・請負は別途ご相談",
          area: "全国対応",
          strengths: "現場人材の在庫と、制度解説を同じメディアで出せます。登録支援機関との連携にも使えます。",
          industry_weakness: "制度改正と悪質ブローカーが多い領域。断定的な許認可アドバイスはせず、一次情報と専門家・公的窓口へ繋ぎます。"
        },
        support_orgs: {
          name: "支援団体",
          name_en: "Support organizations",
          target: "外国人支援団体、国際交流協会、NPO、登録支援機関で、広報や連携先を探している担当者",
          description: "団体の活動紹介、イベント告知、他団体とのつながり、企業・求職者への橋渡しの仕方を掲載します。課金プロフィールの前段として、信頼できる団体情報の受け皿にします。",
          features: ["団体プロフィールの下地", "イベント・相談会の告知", "企業・求職者への紹介導線"],
          keywords: ["外国人支援団体", "国際交流協会", "NPO 外国人", "相談会 外国人", "多文化共生 団体"],
          price_hint: "初期は掲載相談。専用ページ・優先掲載は有料化予定",
          area: "全国",
          strengths: "求職者3,000人と企業リードの間に、団体をハブとして置けます。",
          industry_weakness: "団体情報が散在し、更新されない名簿が多い。掲載基準と連絡先の確認を先に設計します。"
        },
        labor_help: {
          name: "労働トラブル・相談窓口",
          name_en: "Labor issues & help desks",
          target: "賃金未払い、ハラスメント、契約トラブルなど、働き方で困っている外国人",
          description: "労働トラブルの一次整理と、労基署・労働局・法テラス・弁護士会など無料の公的相談先への案内。J Workは法律相談そのものは行わず、正しい窓口へつなぎます。",
          features: ["よくあるトラブルの見分け", "公的窓口の一覧", "相談時に持っていくもの", "緊急時の連絡先"],
          keywords: ["未払い賃金", "労働基準監督署", "ハラスメント 外国人", "法テラス", "労働相談 外国人"],
          price_hint: "案内は無料",
          area: "全国（窓口は都道府県による）",
          strengths: "求人メディアとしての信頼を、相談導線で担保します。",
          industry_weakness: "誤った法律解説はリスクが高い。記事は短く、公式窓口リンクを中心にします。"
        }
      }
    },
    app: {
      ja: "営業代行",
      en: "Sales outsourcing",
      host: ["okurite.pro"],
      service_name: "Okurite",
      columns_index_description: "Okuriteの営業代行・テレアポ・インサイドセールスに関する解説記事一覧。施策設計、KPI、導入事例のポイントをまとめています。",
      strong_points: "AIを活用した低価格かつ大量アプローチを叶えるトータル営業代行サービス",
      keywords: ["営業代行", "テレアポ", "インサイドセールス", "コールセンター", "フォーム営業", "営業KPI", "営業戦略"],
      images: ['app1.jpg', 'app2.jpg'],
      sub_categories: {
        form_marketing: {
          name: "問い合わせフォーム営業",
          name_en: "Inquiry form outreach",
          target: "新規リード獲得を自動化・効率化したいBtoB企業",
          description: "AIや自動化ツールを駆使し、ターゲット企業の問い合わせフォームへ直接アプローチする営業サービス。手動送信とAI自動送信を組み合わせ、高い開封率と返信率を実現します。",
          features: ["AI自動送信ツール活用", "手動アプローチ併用", "送信リスト制作代行", "開封率・返信率最適化", "低コスト大量アプローチ"],
          keywords: ["問い合わせフォーム営業", "フォーム営業自動化", "フォーム営業代行", "リスト制作"],
          price_hint: "要お見積り",
          area: "全国対応",
          strengths: "AIを活用した大量アプローチと、プロのノウハウによる返信率の高い文章設計で、ローコストながら質の高い商談を量産します。",
          industry_weakness: "一般的なフォーム営業は「スパム扱いされやすい」「返信が来ない」のが課題ですが、ターゲット選定の最適化と文面検証により、質の高いリードを獲得します。"
        },
        sales_strategy: {
          name: "営業戦略・プロセス設計",
          name_en: "Sales strategy & process design",
          target: "営業の属人化を解消し、売れる仕組みを作りたい企業",
          description: "リード獲得から商談、受注に至るまでの営業プロセスを構造化。属人化をゼロにし、ターゲット選定から成約率最大化までの全体像を設計するコンサルティング＆代行サービス。",
          features: ["営業プロセス構造化", "ターゲット選定最適化", "属人化の解消", "フルオートメーション化支援"],
          keywords: ["BtoB営業戦略", "営業プロセス設計", "仕組み化", "ターゲット選定"],
          price_hint: "要お見積り",
          area: "全国対応",
          strengths: "1,000社を超える実績に基づく「ターゲット選定」と、成約率を最大化するためのフレームワークを用いた確実な戦略設計が強みです。"
        },
        sales_kpi: {
          name: "営業KPI・数値管理",
          name_en: "Sales KPIs & metrics",
          target: "データに基づいた営業評価や、パイプラインの可視化を行いたい企業",
          description: "MQL（マーケティングリード）からSQL（営業リード）、受注率に至るまでのパイプラインを分解。成果に直結する重要指標（KPI）の正しい設計と、ダッシュボードによる可視化を支援します。",
          features: ["KPI指標設計", "パイプライン管理", "MQL・SQL定義最適化", "ダッシュボード構築支援", "数値分解・改善提案"],
          keywords: ["営業KPI設計", "パイプライン管理", "MQL", "SQL", "受注率向上"],
          price_hint: "要お見積り",
          area: "全国対応",
          strengths: "「機能しないKPI」に陥らないよう、売上に直結する現実的な数値設計と、目標達成のための評価構造をロジカルに構築します。"
        },
        sales_outsourcing: {
          name: "営業アウトソーシング・外注",
          name_en: "Sales outsourcing",
          target: "自社採用のコストを抑え、即戦力の営業プロ集団を活用したい企業",
          description: "インサイドセールスやテレアポ業務を丸ごと任せられるアウトソーシングサービス。最新のAIテレアポ代行から、プロ集団をサブスクリプション型で保有する次世代モデルまで柔軟に対応します。",
          features: ["AIテレアポ代行", "サブスク型営業プロチーム", "フルオートメーション化", "低コスト運用"],
          keywords: ["営業アウトソーシング", "営業代行ガイド", "AIテレアポ", "営業外注"],
          price_hint: "要お見積り",
          area: "全国対応",
          strengths: "累計30,000件以上のアポ獲得経験を持つプロのノウハウとAI技術が融合。自社採用よりも圧倒的に低コストかつスピーディに営業体制を構築します。"
        }
      }
    },
    ai_sales_agent: {
      ja: "AI商談代行",
      en: "AI sales agent",
      host: ["meetia.pro"],
      service_name: "Meetia",
      columns_index_description: "MeetiaのAI商談・営業自動化に関する解説記事一覧。導入手順、活用事例、運用のポイントをまとめています。",
      strong_points: "営業担当者が行う商談工程をAIアバター「ミーティア」が代行。資料アップロードだけで24時間365日即時商談を開始し、商談結果の報告・見込み度分析・自動追客まで一気通貫で営業工数をゼロに。",
      keywords: ["AI商談", "AI商談代行", "AI営業代行", "AIアバター", "24時間商談", "商談自動化", "自動追客"],
      sub_categories: {
        ai_negotiation: {
          name: "24時間即時AI商談",
          name_en: "24/7 instant AI meetings",
          target: "商談工数を削減し、問い合わせ直後の機会損失を防ぎたいBtoB企業",
          description: "営業資料・FAQをアップロードするだけでAIが内容を深く読解。Web上のアバターを介して24時間365日、待機時間ゼロで双方向のヒアリングと提案を自動実行。BANT情報を抽出しCRMへ連携。",
          features: ["資料・FAQの自動解析", "商談スクリプトの自動構成・音声化", "24時間365日即時AI商談", "ユーザー情報・BANT情報の自動抽出", "商談結果の即時レポート", "見込み度（A〜Dランク）の自動判定", "離脱ポイント・関心部分の可視化"],
          keywords: ["AI商談", "AI商談代行", "24時間商談", "AIアバター", "即時商談"],
          price_hint: "フリー ¥0 / ライト ¥30,000 / スタンダード ¥70,000 / プロ ¥150,000 / エンタープライズ カスタム（各月額）",
          area: "全国対応",
          strengths: "資料アップロードのみで即運用開始。深夜・休日のアクセスも取りこぼさず、熱量が最も高い瞬間に質の高い商談を開始。",
          industry_weakness: "従来の営業は担当者依存で対応品質・速度にばらつきがあり、資料請求後の架電タイムラグで競合に流れるケースが多い。Meetiaは即時商談で機会損失を構造的に解消。"
        },
        auto_followup: {
          name: "自動追客・フォローアップ",
          name_en: "Automated follow-up",
          target: "商談後の追客・ステータス管理を自動化し、成約率を安定させたい営業組織",
          description: "AI商談中に導入検討時期や社内調整タイミングを自然な会話でヒアリング。回答時期をトリガーに、最適な追客コンテンツを自動配信。",
          features: ["導入時期に合わせた自動フォロー", "商談ステータス管理", "見込み度に基づく追客シナリオ", "CRM/Slack連携", "お礼メール・定期アプローチの自動化"],
          keywords: ["自動追客", "フォローアップ", "AI営業", "商談後フォロー"],
          price_hint: "プロ ¥150,000/月 / エンタープライズ カスタム（自動追客・シナリオ完全自由）",
          area: "全国対応",
          strengths: "商談から追客までAIが一気通貫で代行。月曜朝には見込み度でセグメントされた商談結果がCRMに並ぶ。",
          industry_weakness: "商談後のフォローは人手依存になりがちで取りこぼしが発生するが、AIが検討時期に合わせた最適タイミングで自動追客。"
        }
      }
    },
    vender: {
      ja: "自販機設置",
      en: "Vending machine installation",
      host: ["自販機.net"],
      service_name: "自動販売機の設置なら『自販機ねっと』",
      columns_index_description: "自販機ねっとの自動販売機設置・購入に関する解説記事一覧。無料設置と購入運営の違い、導入手順、収益の考え方をまとめています。",
      strong_points: "中小企業や小規模企業・個人オーナー向けに自動販売機の購入・販売サービス、大手企業や商店街・繁華街に向けては自動販売機の一括見積もりサービスを提供しております。",
      keywords: ["自販機", "自動販売機"],
      sub_categories: {
        maker_installation: {
          name: "自販機ねっと",
          name_en: "Vending machine placement",
          target: "【集客の多い繁華街や商店街向け】自動販売機を設置・運営したい企業や施設",
          description: "初期費用・月額費用0円のリスクゼロで飲料メーカーの自販機を設置できるサービス。商品の補充、空き缶の回収、売上管理からトラブル対応まで、運営のすべてをメーカーが代行するフルオペレーション型の自動販売機設置プランです。",
          features: ["初期費用0円", "月額費用0円", "商品補充・管理丸投げ", "売上に応じた手数料（販売マージン）収入", "トラブル・故障時の無料対応"],
          keywords: ["自販機 設置", "自動販売機 メーカー", "自販機 無料設置", "自動販売機 運営代行"],
          price_hint: "初期費用・月額費用 0円（電気代のみご負担）",
          area: "全国対応",
          strengths: "主要飲料メーカーから一括で見積もり・条件比較ができるため、最も好条件（高い販売マージンや売れ筋商品）の自動販売機を最適な場所へ設置可能です。",
          industry_weakness: "メーカー自販機は、売上が多く見込める繁華街や駅・商店街に向けて設置可能なプランです。"
        },
        purchase: {
          name: "自動販売機ねっと",
          name_en: "Vending machine purchase",
          target: "メーカーでの設置ができない小規模及び中規模店舗・施設個人様、飲料水以外を販売したい企業",
          description: "新品の自販機本体を購入し、自社で自由に運営するプラン。仕入れや価格設定、商品ラインナップ決定、清掃、空き缶回収までを自社で行うことで、自動販売機の売上利益を最大化できるビジネスモデルです。",
          features: ["高利益", "自由な販売価格設定（格安販売も可能）", "オリジナル商品の販売可（食品・物販など）", "他社にはない最新モデル取扱", "ラッピング自販機対応", "仕入れサポート"],
          keywords: ["自販機 購入", "自動販売機 購入", "オリジナル 自動販売機"],
          price_hint: "本体価格：本体毎に要お見積り（新品80万円〜 ※設置・運搬費別途）",
          area: "全国対応",
          strengths: "飲料だけでなく、社内向けの格安提供（福利厚生）や、地域の特産品・オリジナルグッズ・食品などを販売する特殊な自動販売機の導入・機材選定までトータルで対応可能",
          industry_weakness: "購入後のメンテナンスや故障リスクが懸念される自販機購入ですが、新品購入及びの保証プランにより、購入後のトラブル不安を解消します。"
        }
      }
    },
    # ----------------------------------------------------------------    
    # 追加: 自社記事（Note / Qiita / Zenn など社内転用）
    # ----------------------------------------------------------------    
    ai_article_generation: {
      ja: "自社記事",
      en: "Company articles",
      host: ["drafity.pro"],
      service_name: "Drafify",
      columns_index_description: "DrafifyのAI記事生成・SEOコンテンツに関する解説記事一覧。ピラー／クラスター設計、運用、品質の見方をまとめています。",
      strong_points: "最新AIがGoogleの検索志向を分析し、SEOに強く読者の心に響く高品質な記事を自動生成。ピラー・クラスター構造の設計から、E-E-A-T対応の本文・画像生成、SEOスコア査定、CMS/API連携まで一貫対応。",
      keywords: ["AI記事生成", "SEO記事", "ピラー記事", "クラスター記事", "コンテンツSEO", "E-E-A-T", "コンテンツ資産化"],
      sub_categories: {
        seo_generation: {
          name: "自社記事",
          name_en: "Company articles",
          target: "オウンドメディアの流入を増やし、コンテンツ資産化を進めたい企業・個人",
          description: "AIが検索需要を捉えたテーマを提案し、ピラー記事（親）とクラスター記事（子）を自動設計・生成。約6,000〜8,000字の高品質記事を平均40秒で生成し、SEOスコアで品質を可視化。",
          features: ["テーマ・キーワードの自動提案", "親子記事（ピラー・クラスター）の自動連携", "E-E-A-T対応の高精度記事生成", "画像AI自動生成", "記事ランク・SEOスコア自動査定", "API/CMS連携", "バックグラウンド生成"],
          keywords: ["AI記事生成", "SEO記事", "ピラー記事", "クラスター記事", "コンテンツ資産化"],
          price_hint: "トライアル #{Subscription::TRIAL_DAYS}日間無料（カード不要）/ スタンダード ¥39,800 / ビジネス ¥79,800 / エンタープライズ ¥148,000（各月額・スタンダード初回3ヶ月15%OFF）",
          area: "全国対応",
          strengths: "単なる記事生成ではなく、Google上位表示に適したピラー・クラスター構造の設計から生成・査定まで一貫対応。",
          industry_weakness: "一般的なAIライティングツールは単発記事の量産に留まりSEO構造設計が弱いが、Drafifyはトピッククラスターモデルに基づき検索流入を最大化する設計まで対応。"
        },
        enterprise_agent: {
          name: "自律型AIエージェント",
          name_en: "Autonomous AI agent",
          target: "プロンプト入力を最小限に、AIが主体的に記事量産を行いたい大規模メディア運営者",
          description: "Enterpriseプラン向けの自律型AIエージェント。キーワードを最小限セットするだけで、AIがピラー・クラスター記事を完全自動生成。PCを閉じている間も裏側でタスクが進行。",
          features: ["ピラー・クラスター記事の完全自動生成", "プロンプト最小限の自律稼働", "バックグラウンド処理", "メール・SMSによる進捗通知"],
          keywords: ["AIエージェント", "自律型記事生成", "Enterprise", "メディア量産"],
          price_hint: "エンタープライズ ¥148,000/月（AIエージェント完全自動運用・カスタム機能は個別応相談）",
          area: "全国対応",
          strengths: "人の介入なしでメディア量産。放置するだけで親子記事が次々と完成し、進捗がリアルタイム通知される。",
          industry_weakness: "従来の記事生成は都度のプロンプト入力と人手確認が必要だが、自律エージェントにより運用工数を構造的に削減。"
        }
      }
    },
    # ----------------------------------------------------------------
    # 追加: AI記事（クロール対象ジャンル）
    # ----------------------------------------------------------------
    ai_article: {
      ja: "AI記事",
      en: "AI articles",
      host: ["drafity.pro"],
      service_name: "AI記事生成サービス",
      columns_index_description: "AI記事生成サービスのSEO記事・コンテンツ資産化に関する解説記事一覧。親子記事の作り方と運用のポイントをまとめています。",
      strong_points: "AIを活用し、高品質なSEO記事を自動生成することで、トラフィック増加とコンテンツ資産化を実現",
      keywords: ["AI記事", "AI記事生成", "親記事", "子記事", "SEO記事", "コンテンツSEO", "高品質記事", "コンテンツ資産化"],
      sub_categories: {
        seo_generation: {
          name: "AI記事",
          name_en: "AI articles",
          target: "AI記事生成によってオウンドメディアの流入を増やしたい・コンテンツの資産化を行いたい企業",
          description: "AIを活用して親記事（基幹コンテンツ）を生成し、そこから最適な子記事（派生コンテンツ）を設計・生成することで、検索流入を最大化するコンテンツSEO支援サービス。",
          features: [
            "親記事の自動生成",
            "子記事設計・生成",
            "キーワード構造設計",
            "SEO内部構造最適化",
            "高品質な記事生成",
            "コンテンツ資産化支援"
          ],
          keywords: ["AI記事", "AI記事生成", "SEO記事", "コンテンツ資産化", "高品質記事"],
          price_hint: "要お見積り",
          area: "全国対応",
          strengths: "単なる記事生成ではなく、SEO構造（トピッククラスターモデル）に基づき、検索流入を最大化する設計まで一貫して対応可能です。"
        }
      }
    },
    # ----------------------------------------------------------------
    # Recrivo: AI面接代行
    # ----------------------------------------------------------------
    ai_interview: {
      ja: "AI面接代行",
      en: "AI interview agent",
      host: ["recrivo.pro"],
      service_name: "Recrivo",
      columns_index_description: "RecrivoのAI面接代行に関する解説記事一覧。24時間面接、評価・結果の見方、採用オペレーション改善のポイントをまとめています。",
      strong_points: "求職者との面接をAIが完全代行。24時間いつでも求職者の好きなタイミングで面接ができ、採用結果を把握できるため、応募から面接までのリードタイムを短縮します。",
      keywords: ["AI面接", "AI面接代行", "採用自動化", "オンライン面接", "採用DX", "面接スクリーニング"],
      sub_categories: {
        ai_screening: {
          name: "AI面接・スクリーニング",
          name_en: "AI interview & screening",
          target: "応募増に対して面接工数が逼迫している採用チーム・人事",
          description: "求職者が好きな時間にAI面接を受診。質問・深掘り・評価までを自動化し、採用担当は結果確認と最終判断に集中できる。",
          features: ["24時間面接受付", "質問・深掘りの自動化", "評価結果の可視化", "応募〜面接リードタイム短縮"],
          keywords: ["AI面接", "面接代行", "採用スクリーニング", "24時間面接"],
          price_hint: "要お見積り",
          area: "全国対応",
          strengths: "面接枠の調整や一次面接の工数を大幅に削減し、採用スピードと候補者体験を両立。",
          industry_weakness: "従来の面接は日程調整と一次対応の負荷が大きく取りこぼしが起きやすいが、AI面接で常時受付と初期評価を自動化できる。"
        }
      }
    }
  }.freeze

  # 旧キー互換: meetia → 本体 ai_sales_agent / emergency_cleaning → cleaning
  GENRE_KEY_ALIASES = {
    meetia: :ai_sales_agent,
    emergency_cleaning: :cleaning
  }.freeze

  # 旧中分類 → 現行キー
  SUB_CATEGORY_ALIASES = {
    housekeeping: {
      basic_cleaning: :kaji_daiko
    },
    cleaning: {
      office: :daily_standard,
      school: :daily_standard,
      nursery_school: :daily_standard,
      public_facility: :daily_standard,
      nursing_home: :daily_standard,
      medical_facility: :daily_standard,
      factory: :daily_standard,
      restaurant: :daily_standard,
      building: :apartment
    }
  }.freeze

  class << self
    # URL/DB 上のキーをレジストリ本体キーへ正規化
    def canonical_key(key)
      return nil if key.blank?

      GENRE_KEY_ALIASES.fetch(key.to_sym, key.to_sym).to_s
    end

    def canonical_sub_category_key(genre_key, sub_key)
      return nil if sub_key.blank?

      canon_genre = canonical_key(genre_key)&.to_sym
      aliases = SUB_CATEGORY_ALIASES.fetch(canon_genre, {})
      aliases.fetch(sub_key.to_sym, sub_key.to_sym).to_s
    end

    # 同一ジャンルとして扱うキー一式（本体・別名）
    def equivalent_keys(key)
      return [] if key.blank?

      canonical = canonical_key(key)
      keys = [key.to_s, canonical]
      GENRE_KEY_ALIASES.each do |alias_key, target|
        keys << alias_key.to_s if target.to_s == canonical
      end
      keys.uniq
    end

    def fallback_templates_for(client: nil, host: nil)
      keys = if client.nil?
               FALLBACK_GENRES.keys
             else
               permitted_template_keys_for(client, host).map { |key| key.to_sym }
             end

      keys.each_with_object({}) do |sym, result|
        data = FALLBACK_GENRES[sym]
        next if data.blank?

        result[sym] = { ja: data[:ja] }
      end
    end

    def template_allowed_for_client?(template_key, client:, host: nil)
      return true if client.nil?

      key = template_key.to_s
      return true unless FALLBACK_GENRES.key?(key.to_sym)

      permitted_template_keys_for(client, host).include?(key)
    end

    def custom_genre_key_allowed_for_client?(key, client:)
      return true if client.nil?
      return false if key.blank?

      # 別名キー（meetia 等）は本体キー扱い。カスタム作成不可。
      !FALLBACK_GENRES.key?(canonical_key(key).to_sym)
    end

    def permitted_template_keys_for(client, host)
      allowed = Array(client.allowed_genres).map(&:to_s).reject(&:blank?)
      return [] if allowed.blank?

      allowed_canonical = allowed.map { |k| canonical_key(k) }.uniq
      fallback_keys = FALLBACK_GENRES.keys.map(&:to_s)
      existing = client.service_genres.pluck(:key).map { |k| canonical_key(k) }.uniq
      (allowed_canonical & fallback_keys) - existing
    end

    def resolve_platform_host(request_host, client)
      normalized = normalize_host(request_host)

      if client&.domain.present?
        domain_host = normalize_host(client.domain)
        return domain_host if known_platform_host?(domain_host)
      end

      return normalized if known_platform_host?(normalized)

      if Rails.env.development? && localhost_host?(normalized)
        allowed = Array(client&.allowed_genres).map(&:to_s).reject(&:blank?)
        return "drafity.pro" if (allowed & %w[ai_article ai_article_generation]).any?
      end

      nil
    end

    def template_hosts(data)
      Array(data[:host]).map { |host| normalize_host(host) }.reject(&:blank?)
    end

    def known_platform_host?(host)
      return false if host.blank?

      platform_hosts.include?(normalize_host(host))
    end

    def platform_hosts
      @platform_hosts ||= FALLBACK_GENRES.each_with_object(Set.new) do |(_key, data), set|
        template_hosts(data).each { |value| set << value }
      end
    end

    def normalize_host(host)
      host.to_s.downcase.sub(/\Awww\./, "").split(":").first
    end

    def localhost_host?(host)
      host.in?(%w[localhost 127.0.0.1 0.0.0.0])
    end

    def genres(client: nil)
      cache_key = client&.id || :global
      runtime_cache[cache_key] ||= load_genres(client)
    end

    def reset!
      Rails.application.instance_variable_set(:@genre_registry_cache, {})
      @platform_hosts = nil
      remove_const(:GENRES) if const_defined?(:GENRES, false)
    end

    def genre_keys
      genres.keys.map(&:to_s)
    end

    def const_missing(name)
      if name == :GENRES
        const_set(:GENRES, genres)
      else
        super
      end
    end

    private

    def runtime_cache
      Rails.application.instance_variable_get(:@genre_registry_cache) ||
        Rails.application.instance_variable_set(:@genre_registry_cache, {})
    end

    def load_genres(client)
      if client
        return {} unless service_genres_table_ready?

        result = ServiceGenre.where(client_id: client.id).order(:ja).each_with_object({}) do |record, hash|
          hash[record.key.to_sym] = merge_fallback_i18n(record.key, record.to_registry_hash)
        end
        collapse_aliased_genre_keys!(result)
      else
        result = FALLBACK_GENRES.dup
        return result unless service_genres_table_ready?

        ServiceGenre.where(client_id: nil).find_each do |record|
          result[record.key.to_sym] = merge_fallback_i18n(record.key, record.to_registry_hash)
        end
        collapse_aliased_genre_keys!(result)
      end
    end

    def merge_fallback_i18n(key, hash)
      fallback = FALLBACK_GENRES[canonical_key(key)&.to_sym]
      return hash if fallback.blank? || !hash.is_a?(Hash)

      hash[:en] = hash[:en].presence || fallback[:en]
      fb_subs = fallback[:sub_categories] || {}
      unless hash[:sub_categories].is_a?(Hash)
        hash[:sub_categories] = fb_subs.is_a?(Hash) ? fb_subs.deep_dup : {}
      end
      subs = hash[:sub_categories]
      return hash unless subs.is_a?(Hash)

      subs.each do |sub_key, sub|
        next unless sub.is_a?(Hash)

        fb = fb_subs[sub_key.to_sym] || fb_subs[sub_key.to_s]
        next unless fb.is_a?(Hash)

        sub[:name_en] = sub[:name_en].presence || fb[:name_en]
      end
      hash
    end

    # 別名キーと本体が同時に載らないよう、本体キーへ寄せる
    def collapse_aliased_genre_keys!(result)
      GENRE_KEY_ALIASES.each do |alias_key, target|
        alias_sym = alias_key.to_sym
        target_sym = target.to_sym
        next unless result.key?(alias_sym)

        if result.key?(target_sym)
          result.delete(alias_sym)
        else
          result[target_sym] = result.delete(alias_sym)
        end
      end
      result
    end

    def service_genres_table_ready?
      ActiveRecord::Base.connection.data_source_exists?("service_genres")
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
      false
    end
  end

  # --- ヘルパーメソッド ---

  def self.from_ja(ja)
    return nil if ja.blank?
    return "ai_article_generation" if ja.to_s == "AI記事生成"

    genres.find { |_, v| v[:ja] == ja }&.first&.to_s
  end

  def self.resolve_key(genre, client: nil)
    return nil if genre.blank?

    registry = genres(client: client)
    key_str = canonical_key(genre)
    return key_str if registry.key?(key_str.to_sym)

    from_ja_key = from_ja(genre.to_s)
    if from_ja_key.present?
      from_ja_canon = canonical_key(from_ja_key)
      return from_ja_canon if registry.key?(from_ja_canon.to_sym)
    end

    key_str
  end

  def self.to_ja(key, client: nil)
    return nil if key.blank?

    genre_entry(key, client: client)&.dig(:ja)
  end

  def self.to_en(key, client: nil)
    return nil if key.blank?

    genre_entry(key, client: client)&.dig(:en).presence ||
      FALLBACK_GENRES.dig(canonical_key(key)&.to_sym, :en)
  end

  def self.label_for(key, client: nil, locale: I18n.locale)
    entry = genre_entry(key, client: client)
    fallback = key.to_s
    return fallback if entry.blank?

    if locale.to_s == "en"
      entry[:en].presence || to_en(key) || entry[:ja].presence || fallback
    else
      entry[:ja].presence || entry[:en].presence || fallback
    end
  end

  # クライアント固有定義を優先し、なければグローバル定義を返す
  def self.genre_entry(key, client: nil)
    return nil if key.blank?

    canon = canonical_key(key)&.to_sym
    if client
      entry = genres(client: client)[canon]
      return entry if entry.present?
    end

    genres[canon]
  end

  def self.sub_category_label(genre_key, sub_key, client: nil, locale: I18n.locale)
    return sub_key.to_s if sub_key.blank?

    entry = genre_entry(genre_key, client: client)
    subs = entry&.dig(:sub_categories) || {}
    lookup = canonical_sub_category_key(genre_key, sub_key)
    sub = subs[lookup.to_sym] || subs[lookup] || subs[sub_key.to_sym] || subs[sub_key.to_s]
    return sub_key.to_s if sub.blank?

    if locale.to_s == "en"
      sub[:name_en].presence ||
        FALLBACK_GENRES.dig(canonical_key(genre_key)&.to_sym, :sub_categories, sub_key.to_sym, :name_en).presence ||
        sub[:name].presence ||
        sub_key.to_s
    else
      sub[:name].presence || sub[:name_en].presence || sub_key.to_s
    end
  end

  # 保存済み中分類を優先。未設定時のみキーワードから推定する
  def self.resolve_sub_category_key(column, genre_key, client: nil)
    genre = genre_entry(genre_key, client: client)
    subs = genre&.dig(:sub_categories)
    return nil unless subs.is_a?(Hash)
    return nil if subs.blank?

    saved = column.sub_genre.to_s
    saved_canon = canonical_sub_category_key(genre_key, saved)
    if saved_canon.present? && (subs.key?(saved_canon.to_sym) || subs.key?(saved_canon))
      return saved_canon
    end

    text = [
      column.title,
      column.keyword,
      column.prompt,
      column.description
    ].join(" ")

    subs.each do |key, sub|
      next unless sub.is_a?(Hash)
      next unless sub[:keywords]

      return key.to_s if sub[:keywords].any? { |w| text.include?(w) }
    end

    nil
  end

  # AI生成用のプロフィール。中分類がある場合はそれを優先する
  def self.service_profile(category_key, sub_key = nil, client: nil)
    return "専門知識に基づいた最適なソリューションを提供。" if category_key.blank?

    g = genre_entry(category_key, client: client)
    return "専門知識に基づいた最適なソリューションを提供。" unless g

    if sub_key && g[:sub_categories] && g[:sub_categories][sub_key.to_sym]
      s = g[:sub_categories][sub_key.to_sym]
      return <<~TEXT
        サービス名: #{g[:service_name]}（#{s[:name]}）
        ターゲット: #{s[:target]}
        内容: #{s[:description]}
        特徴: #{Array(s[:features]).join('、')}
        料金: #{s[:price_hint]}
        強み: #{s[:strengths]}
        業界の課題と弊社の立ち位置: #{s[:industry_weakness]}
      TEXT
    end

    "サービス名: #{g[:service_name]}\n強み: #{g[:strong_points]}"
  end

  # 元々定義されていたメソッド（Controllerで使用するため必須）
  def self.allowed_hosts(host)
    genres.find { |_, v| v[:host].include?(host) }&.first
  end

  # 画像取得用
  def self.images(key, client: nil)
    genres(client: client)[canonical_key(key)&.to_sym]&.dig(:images) || []
  end

  # キーワード取得用
  def self.keywords(ja, client: nil)
    genres(client: client)[from_ja(ja)&.to_sym]&.dig(:keywords) || []
  end

  # 記事一覧ページ用の meta description（ジャンル定義に無ければ自動生成）
  def self.columns_index_description(key, client: nil, locale: I18n.locale)
    entry = genre_entry(key, client: client)
    return nil if entry.blank?

    if locale.to_s == "en"
      stored_en = entry[:columns_index_description_en].to_s.strip
      return stored_en if stored_en.present?

      name = label_for(key, client: client, locale: :en)
      return "#{name}: guides, operations tips, and case studies."
    end

    stored = entry[:columns_index_description].to_s.strip
    return stored if stored.present?

    name = entry[:service_name].presence || entry[:ja].presence || key.to_s
    tip = entry[:strong_points].to_s.gsub(/\s+/, " ").strip
    tip = tip.truncate(70) if tip.present?
    if tip.present?
      "#{name}に関する解説記事一覧。#{tip}"
    else
      "#{name}に関する解説記事一覧。導入・運用・事例のポイントをまとめています。"
    end
  end
end