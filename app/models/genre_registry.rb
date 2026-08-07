module GenreRegistry
  FALLBACK_GENRES = {
    cleaning: {
      ja: "清掃",
      host: ["okey.work"],
      service_name: "OK清掃",
      columns_index_description: "OK清掃の日常清掃・オフィス清掃・施設清掃に関する解説記事一覧。導入の進め方、運用ポイント、現場の事例をまとめています。",
      keywords: ["日常清掃", "オフィス清掃", "学校清掃", "施設清掃", "店舗清掃"],
      sub_categories: {
        daily_standard: {
          name: "日常清掃",
          target: "清掃美化を外注したい企業や施設・ビル",
          description: "週1回〜・1日3時間〜、決まった時間にスタッフが訪問する清掃サービス。トイレ掃除、ゴミ回収、床掃除など、建物の美観と衛生を維持する基本サービス。",
          features: ["週1回〜", "1回3時間〜の時間清掃", "清掃報告書発行", "深夜対応", "スタッフ固定制", "時間割引対応", "20〜50代中心"],
          keywords: ["日常清掃", "施設清掃"],
          price_hint: "時給3,000円〜 / 月額21,600円〜",
          area: "全国対応",
          strengths: "人材紹介業出身の清掃業である特性から、20〜50代の人材が中心。安定した清掃人材の提供が可能。",
          industry_weakness: "一般的に『人が足りない』『60〜80代中心』が日常清掃の最大課題ですが、OK清掃は若くて動ける人材が多いのが特徴です。"
        },
        office: {
          name: "オフィス清掃",
          target: "企業のオフィス・事務所、執室",
          description: "デスク周りのゴミ回収、会議室、給湯室、役員室などの清掃。機密情報（Pマーク・ISMS取得企業など）への配慮や、PC機器・配線周りの丁寧な取り扱いを徹底します。",
          features: ["機密保持・セキュリティ遵守", "ゴミ分別・回収", "什器への配慮", "深夜・早朝の無人対応可"],
          keywords: ["オフィス清掃", "事務所掃除", "執室清掃"],
          price_hint: "要お見積り（頻度・平米数による）",
          area: "全国対応",
          strengths: "オフィス特有のセキュリティルールやマナー教育を修了したスタッフが対応するため、シュレッダーゴミの処理なども安心してお任せいただけます。",
          industry_weakness: "オフィス特有のセキュリティや什器の扱いに慣れていない業者が多い中、事前のマニュアル化でトラブルを防止します。"
        },
        school: {
          name: "学校・学習塾清掃",
          target: "小・中・高校、大学、専門学校、大手学習塾など",
          description: "教室、廊下、階段、トイレ、体育館などの日常清掃。生徒・学生が学習に集中できる環境をつくるとともに、長期休み（夏休み等）に合わせた柔軟なシフト調整に対応します。",
          features: ["長期休暇中のシフト調整可", "黒板・教壇周り清掃", "ゴミ回収", "トイレの徹底洗浄"],
          keywords: ["学校清掃", "塾掃除", "校舎清掃"],
          price_hint: "要お見積り",
          area: "全国対応",
          strengths: "若手〜中堅スタッフ中心のため、広い校舎でも機敏に動き、時間内に効率よく清掃を完了させます。"
        },
        nursery_school: {
          name: "保育園・幼稚園清掃",
          target: "認可・認可外保育園、幼稚園、こども園",
          description: "園児たちが素足やハイハイで触れる床、おもちゃ、手すりなどの徹底的な洗浄と除菌。ノンケミカル（環境や人体に優しい）な洗剤の選定など、安全を最優先にした清掃を行います。",
          features: ["安全な洗剤・薬剤の選定", "徹底した除菌・ウイルス対策", "園児の安全への配慮（コード類の排除等）"],
          keywords: ["保育園清掃", "幼稚園掃除", "こども園清掃"],
          price_hint: "要お見積り",
          area: "全国対応",
          strengths: "20〜50代の丁寧でコミュニケーション力のあるスタッフが、先生方や園児、保護者の目にも安心・安全に映るよう配慮して作業します。",
          industry_weakness: "園児の誤飲やアレルギーに配慮した洗剤選定や、徹底した衛生基準の維持は一般的な清掃業者では対応が難しいですが、OK清掃では独自の衛生マニュアルを運用しています。"
        },
        public_facility: {
          name: "施設清掃",
          target: "商業施設、大型店舗、ショールームなど",
          description: "不特定多数が利用する施設の清掃・美化。営業時間を妨げない柔軟なシフトで、お客様に選ばれる綺麗な空間を維持します。",
          features: ["巡回清掃", "土日祝対応", "開館前・閉館後対応", "大規模施設対応"],
          keywords: ["施設清掃", "商業施設掃除", "店舗清掃"],
          price_hint: "要お見積り",
          area: "全国対応",
          strengths: "動ける20〜50代スタッフが中心のため、広い施設でもスピーディかつ隅々まで行き届いた清掃が可能です。"
        },
        nursing_home: {
          name: "介護施設清掃",
          target: "有料老人ホーム、デイサービス、サ高住など",
          description: "入居者様・利用者様が安心して過ごせる衛生環境を維持。施設特有のにおい対策や、徹底した除菌清掃を行います。",
          features: ["除菌・消臭", "入居者様への挨拶・マナー徹底", "感染症対策", "日中常駐可"],
          keywords: ["介護施設清掃", "老人ホーム掃除", "デイサービス清掃"],
          price_hint: "要お見積り",
          area: "全国対応",
          strengths: "20〜50代のコミュニケーション力の高いスタッフが中心のため、入居者様や施設職員様とも良好な関係を築けます。"
        },
        medical_facility: {
          name: "医療施設清掃",
          target: "病院、クリニック、歯科医院など",
          description: "院内感染防止を最優先にした衛生管理清掃。区域ごとのモップの使い分け（カラーゾーニング）など、医療環境基準に準拠した作業を行います。",
          features: ["カラーゾーニング（使い分け）", "院内感染対策", "専門研修受講スタッフ"],
          keywords: ["医療施設清掃", "病院清掃", "クリニック掃除"],
          price_hint: "要お見積り",
          area: "全国対応",
          industry_weakness: "一般的な清掃業者が敬遠しがちな、厳しい衛生基準が求められる医療現場にも、教育された若手・中堅スタッフを安定投入できます。"
        },
        factory: {
          name: "工場清掃",
          target: "製造工場、物流倉庫、センターなど",
          description: "通路や休憩室、食堂などの日常清掃。工場の安全ルール・5S（整理・整頓・清掃・清潔・しつけ）を遵守して行動します。",
          features: ["安全第一", "広範囲対応", "作業着・安全靴着用", "5S徹底"],
          keywords: ["工場清掃", "倉庫清掃", "物流センター掃除"],
          price_hint: "要お見積り",
          area: "全国対応",
          strengths: "体力のある若い人材が多いため、広大な敷地や特殊な環境の清掃もタフに対応します。"
        },
        restaurant: {
          name: "飲食清掃",
          target: "居酒屋、レストラン、カフェなど",
          description: "ホール、トイレ、厨房の基本清掃。開店前の清潔な空間づくりや、閉店後の夜間・深夜清掃に対応します。",
          features: ["深夜・早朝対応", "油汚れ対応", "害虫対策", "衛生維持"],
          keywords: ["飲食店清掃", "店舗清掃", "厨房掃除"],
          price_hint: "要お見積り",
          area: "全国対応",
          strengths: "店舗の営業時間を妨げない深夜・早朝のシフト組が強みです。"
        },
        apartment: {
          name: "マンション・アパート巡回清掃",
          target: "不動産管理会社、物件オーナー、大家様",
          description: "週1回や月2回など、決まった頻度で物件を巡回。エントランス、廊下、階段の掃き拭き、ゴミ置き場の整理、電球交換などを行います。",
          features: ["写真付き報告書", "簡易点検（電球切れ等）", "ゴミ置き場清掃", "複数物件一括対応"],
          keywords: ["マンション巡回清掃", "アパート清掃", "共用部掃除"],
          price_hint: "1棟あたり 月額数千円〜（棟数・階数による）",
          area: "全国対応",
          strengths: "写真報告システムが標準化されているため、遠方の大家様でも物件の状況が一目でわかります。"
        },
        building: {
          name: "ビル巡回清掃",
          target: "雑居ビル、中小規模ビルのオーナー・管理会社",
          description: "テナントビルや雑居ビルの共有部（階段、エレベーター、共用トイレなど）を定期巡回し、資産価値とテナント満足度を維持します。",
          features: ["共用部清掃", "定期巡回", "不法投棄チェック", "報告書提出"],
          keywords: ["ビル巡回清掃", "雑居ビル掃除", "ビル共有部清掃"],
          price_hint: "要お見積り",
          area: "全国対応"
        },
        periodic: {
          name: "定期清掃（床・ガラス等）",
          target: "オフィス、店舗、ビル、施設全般",
          description: "数ヶ月に1回、日常清掃では落とせない汚れを専用の機械（ポリッシャー、高圧洗浄機）を用いて徹底的に洗浄。床のワックス掛けや高所ガラス清掃を行います。",
          features: ["床ポリッシャー洗浄", "ワックス塗布", "高所ガラス清掃", "カーペット洗浄"],
          keywords: ["定期清掃", "床ワックスがけ", "ガラス清掃", "高圧洗浄"],
          price_hint: "1回あたり要見積もり（平米数による単価設定）",
          area: "全国対応"
        },
        turnover: {
          name: "原状回復工事・清掃",
          target: "賃貸物件の大家様、管理会社",
          description: "入居者の退去後、次の入居者を迎えるための丸ごとハウスクリーニング。必要に応じてクロスの張り替えや小修繕、設備交換までワンストップで対応します。",
          features: ["空室全体清掃", "クロス・床張り替え", "水回り徹底洗浄", "パッキン交換等小修繕"],
          keywords: ["原状回復清掃", "退去後クリーニング", "空室清掃", "クロス張り替え"],
          price_hint: "間取り（1K・2LDK等）に応じた定額制あり",
          area: "全国対応",
          strengths: "清掃だけでなく内装・修繕まで一括で引き受けられるため、発注の手間を大幅に削減。空室期間を最短化します。"
        }
      }
    },
    housekeeping: {
      ja: "家事代行",
      host: ["kurasera.life"],
      service_name: "クラセラ",
      columns_index_description: "クラセラの家事代行・ハウスクリーニングに関する解説記事一覧。依頼の流れ、料金の考え方、活用事例をまとめています。",
      keywords: ["家事代行", "お手伝いさん", "家政婦", "ハウスキーピング"],
      strong_points: "家事代行・お手伝いさん・家政婦・ハウスキーピングの依頼なら『クラセラ』",
      sub_categories: {
        basic_cleaning: {
          name: "家事代行",
          target: "日常的な家事負担を減らしたい個人・家庭",
          description: "掃除・洗濯・片付け・買い物代行など、日常生活の家事全般をサポートする基本プラン。",
          features: ["掃除対応", "洗濯対応", "片付け", "買い物代行", "柔軟な時間設定"],
          keywords: ["家事代行", "掃除代行", "家政婦サービス"],
          price_hint: "1時間3000円〜",
          area: "全国対応",
          strengths: "利用者の生活スタイルに合わせて柔軟に対応できる点が強みです。"
        }
      }
    },
    pest: {
      ja: "シロアリ駆除",
      host: [],
      service_name: "シロアリ害虫駆除なら『シロアリ駆除士隊』",
      columns_index_description: "シロアリ駆除・害虫対策に関する解説記事一覧。調査から施工、再発防止までのポイントをまとめています。",
      keywords: ["シロアリ駆除"],
      strong_points: "自宅のシロアリにお悩みの方に向けて害虫の駆除を行います。",
      sub_categories: {
        termite_control: {
          name: "シロアリ駆除",
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
    # ----------------------------------------------------------------
    # 5. 特殊清掃（緊急・専門事案）
    # ----------------------------------------------------------------
    emergency_cleaning: {
      ja: "特殊清掃",
      host: ["okey.work"],
      service_name: "OK特殊クリーンサービス",
      columns_index_description: "OK特殊クリーンの特殊清掃・遺品整理に関する解説記事一覧。対応範囲、消臭・除菌、依頼時の注意点をまとめています。",
      keywords: ["特殊清掃", "遺品整理", "孤独死清掃", "ゴミ屋敷片付け", "特殊消臭"],
      sub_categories: {
        special: {
          name: "特殊清掃・遺品整理",
          target: "物件オーナー、遺族、管理会社",
          description: "孤独死や変死のあった現場の事件現場特殊清掃。通常の清掃では不可能な、体液・血液の除去、害虫駆除、専用機材（オゾン脱臭機等）による完全消臭を行います。",
          features: ["24時間緊急対応", "完全消臭（オゾン燻蒸）", "遺品整理・不用品回収", "除菌・消毒徹底"],
          keywords: ["特殊清掃", "孤独死清掃", "遺品整理", "ゴミ屋敷片付け", "オゾン消臭"],
          price_hint: "状況により要見積り（緊急対応可）",
          area: "全国対応",
          strengths: "特殊な薬剤と高濃度オゾン脱臭機を用いて、臭いを『元から断つ』プロの技術。近隣住民への配慮も徹底します。"
        }
      }
    },
    cargo: {
      ja: "Amazon配送",
      host: ["okey.work"],
      service_name: "J Work",
      columns_index_description: "J WorkのAmazon配送・軽貨物ドライバー支援に関する解説記事一覧。採用、請負、現場運営のポイントをまとめています。",
      keywords: ["Amazonデリバリー", "軽貨物配送", "配送ドライバー"],
      sub_categories: {
        delivery_partner: {
          name: "Amazon配送デリバリースタッフ支援",
          target: "Amazonの配送業務を受託しており、ドライバー確保に課題がある企業",
          description: "Amazon配送に特化したドライバーの供給サービス。全国でAmazon配送を行いたい人材を提供し、請負致します。",
          features: ["全国対応", "外国人配送ドライバー", "配達人材の確保力"],
          keywords: ["Amazon配送", "ドライバー採用", "Amazon配送業務請負"],
          price_hint: "御社の単価そのままで業務請負 / 人材紹介可",
          area: "関東・関西・名古屋中心に全国でドライバー人材を手配可能",
          strengths: "人材紹介業のノウハウを活かし、毎月500名の日本語の話せる永住ビザ人材からドライバー応募を頂いております。他社が苦戦する「体力のあるドライバー」を優先的に確保。定着率の高さが強みです。",
          industry_weakness: "軽貨物業界は「高齢化」と「慢性的な人手不足」が深刻ですが、J Workは独自の集客ルートで20〜50代の稼働人数を最大化しています。"
        },
        driver_recruitment: {
          name: "Amazon配送ドライバー採用",
          target: "Amazonの配送員として働きたい個人・求職者",
          description: "Amazonの荷物を個人宅へ届ける軽貨物ドライバーの募集。専用アプリの操作から効率的な積み込み方法まで、未経験からでも月収40万円以上を目指せる環境を提供します。",
          features: ["未経験歓迎", "車両貸出制度あり", "直行直帰OK", "研修制度充実", "外国人歓迎", "英語アプリで簡単配送"],
          keywords: ["軽バン配送", "高収入求人", "業務委託ドライバー", "Amazonドライバー求人"],
          price_hint: "月収400,000円以上",
          area: "関東・関西・愛知中心に全国対応",
          strengths: "日給で安定して稼げるフルタイムのAmazon稼働スタッフを常時募集中。日本人はもちろん、外国人も働ける求人です。",
          industry_weakness: "「現場に放り出されて終わり」という会社が多い中、丁寧に横乗りからスタートしますので、未経験から安心してお仕事が可能です。"
        }
      }
    },
    app: {
      ja: "営業代行",
      host: ["okurite.pro"],
      service_name: "Okurite",
      columns_index_description: "Okuriteの営業代行・テレアポ・インサイドセールスに関する解説記事一覧。施策設計、KPI、導入事例のポイントをまとめています。",
      strong_points: "AIを活用した低価格かつ大量アプローチを叶えるトータル営業代行サービス",
      keywords: ["営業代行", "テレアポ", "インサイドセールス", "コールセンター", "フォーム営業", "営業KPI", "営業戦略"],
      images: ['app1.jpg', 'app2.jpg'],
      sub_categories: {
        form_marketing: {
          name: "問い合わせフォーム営業",
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
      host: ["meetia.pro"],
      service_name: "Meetia",
      columns_index_description: "MeetiaのAI商談・営業自動化に関する解説記事一覧。導入手順、活用事例、運用のポイントをまとめています。",
      strong_points: "営業担当者が行う商談工程をAIアバター「ミーティア」が代行。資料アップロードだけで24時間365日即時商談を開始し、商談結果の報告・見込み度分析・自動追客まで一気通貫で営業工数をゼロに。",
      keywords: ["AI商談", "AI商談代行", "AI営業代行", "AIアバター", "24時間商談", "商談自動化", "自動追客"],
      sub_categories: {
        ai_negotiation: {
          name: "24時間即時AI商談",
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
      host: ["自販機.net"],
      service_name: "自動販売機の設置なら『自販機ねっと』",
      columns_index_description: "自販機ねっとの自動販売機設置・購入に関する解説記事一覧。無料設置と購入運営の違い、導入手順、収益の考え方をまとめています。",
      strong_points: "中小企業や小規模企業・個人オーナー向けに自動販売機の購入・販売サービス、大手企業や商店街・繁華街に向けては自動販売機の一括見積もりサービスを提供しております。",
      keywords: ["自販機", "自動販売機"],
      sub_categories: {
        maker_installation: {
          name: "自販機ねっと",
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
    # 追加: AI記事生成    
    # ----------------------------------------------------------------    
    ai_article_generation: {
      ja: "AI記事生成",
      host: ["drafity.pro"],
      service_name: "Drafify",
      columns_index_description: "DrafifyのAI記事生成・SEOコンテンツに関する解説記事一覧。ピラー／クラスター設計、運用、品質の見方をまとめています。",
      strong_points: "最新AIがGoogleの検索志向を分析し、SEOに強く読者の心に響く高品質な記事を自動生成。ピラー・クラスター構造の設計から、E-E-A-T対応の本文・画像生成、SEOスコア査定、CMS/API連携まで一貫対応。",
      keywords: ["AI記事生成", "SEO記事", "ピラー記事", "クラスター記事", "コンテンツSEO", "E-E-A-T", "コンテンツ資産化"],
      sub_categories: {
        seo_generation: {
          name: "AI記事生成",
          target: "オウンドメディアの流入を増やし、コンテンツ資産化を進めたい企業・個人",
          description: "AIが検索需要を捉えたテーマを提案し、ピラー記事（親）とクラスター記事（子）を自動設計・生成。約6,000〜8,000字の高品質記事を平均40秒で生成し、SEOスコアで品質を可視化。",
          features: ["テーマ・キーワードの自動提案", "親子記事（ピラー・クラスター）の自動連携", "E-E-A-T対応の高精度記事生成", "画像AI自動生成", "記事ランク・SEOスコア自動査定", "API/CMS連携", "バックグラウンド生成"],
          keywords: ["AI記事生成", "SEO記事", "ピラー記事", "クラスター記事", "コンテンツ資産化"],
          price_hint: "無料プラン 月3記事（クレカ不要・ずっと無料）/ トライアル #{Subscription::TRIAL_DAYS}日間無料 / スターター ¥29,800 / スタンダード ¥49,800 / ビジネス ¥98,000 / エンタープライズ ¥198,000（各月額・年額20%OFF）",
          area: "全国対応",
          strengths: "単なる記事生成ではなく、Google上位表示に適したピラー・クラスター構造の設計から生成・査定まで一貫対応。",
          industry_weakness: "一般的なAIライティングツールは単発記事の量産に留まりSEO構造設計が弱いが、Drafifyはトピッククラスターモデルに基づき検索流入を最大化する設計まで対応。"
        },
        enterprise_agent: {
          name: "自律型AIエージェント",
          target: "プロンプト入力を最小限に、AIが主体的に記事量産を行いたい大規模メディア運営者",
          description: "Enterpriseプラン向けの自律型AIエージェント。キーワードを最小限セットするだけで、AIがピラー・クラスター記事を完全自動生成。PCを閉じている間も裏側でタスクが進行。",
          features: ["ピラー・クラスター記事の完全自動生成", "プロンプト最小限の自律稼働", "バックグラウンド処理", "メール・SMSによる進捗通知"],
          keywords: ["AIエージェント", "自律型記事生成", "Enterprise", "メディア量産"],
          price_hint: "エンタープライズ ¥198,000/月（年額20%OFF・AIエージェント完全自動運用・カスタム機能は個別応相談）",
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
      host: ["drafity.pro"],
      service_name: "AI記事生成サービス",
      columns_index_description: "AI記事生成サービスのSEO記事・コンテンツ資産化に関する解説記事一覧。親子記事の作り方と運用のポイントをまとめています。",
      strong_points: "AIを活用し、高品質なSEO記事を自動生成することで、トラフィック増加とコンテンツ資産化を実現",
      keywords: ["AI記事", "AI記事生成", "親記事", "子記事", "SEO記事", "コンテンツSEO", "高品質記事", "コンテンツ資産化"],
      sub_categories: {
        seo_generation: {
          name: "AI記事",
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
      host: ["recrivo.pro"],
      service_name: "Recrivo",
      columns_index_description: "RecrivoのAI面接代行に関する解説記事一覧。24時間面接、評価・結果の見方、採用オペレーション改善のポイントをまとめています。",
      strong_points: "求職者との面接をAIが完全代行。24時間いつでも求職者の好きなタイミングで面接ができ、採用結果を把握できるため、応募から面接までのリードタイムを短縮します。",
      keywords: ["AI面接", "AI面接代行", "採用自動化", "オンライン面接", "採用DX", "面接スクリーニング"],
      sub_categories: {
        ai_screening: {
          name: "AI面接・スクリーニング",
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

  # 旧キー互換: meetia → 本体 ai_sales_agent
  GENRE_KEY_ALIASES = {
    meetia: :ai_sales_agent
  }.freeze

  class << self
    # URL/DB 上のキーをレジストリ本体キーへ正規化
    def canonical_key(key)
      return nil if key.blank?

      GENRE_KEY_ALIASES.fetch(key.to_sym, key.to_sym).to_s
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
      return FALLBACK_GENRES.deep_dup if client.nil?

      permitted_template_keys_for(client, host).each_with_object({}) do |key, result|
        sym = key.to_sym
        result[sym] = FALLBACK_GENRES[sym] if FALLBACK_GENRES.key?(sym)
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

      FALLBACK_GENRES.values.any? { |data| template_hosts(data).include?(host) }
    end

    def normalize_host(host)
      host.to_s.downcase.sub(/\Awww\./, "").split(":").first
    end

    def localhost_host?(host)
      host.in?(%w[localhost 127.0.0.1 0.0.0.0])
    end

    def genres(client: nil)
      cache = (@genres_cache ||= {})
      cache_key = client&.id || :global
      cache[cache_key] ||= load_genres(client)
    end

    def reset!
      @genres_cache = nil
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

    def load_genres(client)
      if client
        return {} unless service_genres_table_ready?

        result = ServiceGenre.where(client_id: client.id).order(:ja).each_with_object({}) do |record, hash|
          hash[record.key.to_sym] = record.to_registry_hash
        end
        collapse_aliased_genre_keys!(result)
      else
        result = FALLBACK_GENRES.deep_dup
        return result unless service_genres_table_ready?

        ServiceGenre.where(client_id: nil).find_each do |record|
          result[record.key.to_sym] = record.to_registry_hash
        end
        collapse_aliased_genre_keys!(result)
      end
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

  # 保存済み中分類を優先。未設定時のみキーワードから推定する
  def self.resolve_sub_category_key(column, genre_key, client: nil)
    genre = genre_entry(genre_key, client: client)
    subs = genre&.dig(:sub_categories)
    return nil if subs.blank?

    saved = column.sub_genre.to_s
    if saved.present? && (subs.key?(saved.to_sym) || subs.key?(saved))
      return saved
    end

    text = [
      column.title,
      column.keyword,
      column.prompt,
      column.description
    ].join(" ")

    subs.each do |key, sub|
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
  def self.columns_index_description(key, client: nil)
    entry = genre_entry(key, client: client)
    return nil if entry.blank?

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