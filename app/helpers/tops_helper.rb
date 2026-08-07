module TopsHelper
  # Draftiy 自社サイト（drafity.pro）の公開 columns は ai_article のみ。
  # 他ジャンル（vender/app/cargo 等）はここに絶対に出さない。
  AI_ARTICLE_COLUMNS_INDEX = "/#{CrawlPolicy::GENRE_KEY}/columns".freeze

  # DB 未接続・記事0件時のフォールバック（いずれも /ai_article/columns/* のみ）
  AI_ARTICLE_FEATURED_FALLBACK = [
    { title: "GEOを活用した効果的なコンテンツ戦略", path: "/ai_article/columns/geo-content-strategy" },
    { title: "SEOの未来を見据えたAI技術の活用法", path: "/ai_article/columns/ai-article-generation-seo-future" },
    { title: "AI記事生成ツールの選び方と活用法", path: "/ai_article/columns/ai-article-generation-tool-selection-and-utilization" },
    { title: "量産型ブログの落とし穴と対策", path: "/ai_article/columns/ryousangata-blog-no-otoshiana-to-taisaku" },
    { title: "SEOに強いAI記事を作るためのステップバイステップ", path: "/ai_article/columns/seo-ai-article-creation-steps" }
  ].freeze
 
  AI_ARTICLE_FEATURED_FALLBACK_EN = [
    { title: "GEO-powered content strategy that works", path: "/ai_article/columns/geo-content-strategy" },
    { title: "Using AI for the next era of SEO", path: "/ai_article/columns/ai-article-generation-seo-future" },
    { title: "How to choose and use AI writing tools", path: "/ai_article/columns/ai-article-generation-tool-selection-and-utilization" },
    { title: "Pitfalls of mass-produced blogs — and fixes", path: "/ai_article/columns/ryousangata-blog-no-otoshiana-to-taisaku" },
    { title: "Step-by-step: SEO-strong AI articles", path: "/ai_article/columns/seo-ai-article-creation-steps" }
  ].freeze

  def lp_english?
    I18n.locale.to_s == "en"
  end

  def ai_article_columns_index_path
    AI_ARTICLE_COLUMNS_INDEX
  end

  def featured_ai_article_columns(limit: 5)
    live = CrawlPolicy.crawlable_columns
                      .order(updated_at: :desc)
                      .limit(limit)
                      .filter_map do |column|
      next if column.code.blank?
      next unless GenreRegistry.equivalent_keys(column.genre).include?(CrawlPolicy::GENRE_KEY)

      { title: column.title, path: CrawlPolicy.column_path(column) }
    end

    return live if live.any?

    featured_fallback.first(limit)
  rescue StandardError
    featured_fallback.first(limit)
  end

  def featured_fallback
    lp_english? ? AI_ARTICLE_FEATURED_FALLBACK_EN : AI_ARTICLE_FEATURED_FALLBACK
  end

  def lp_whats_features
    if lp_english?
      [
        { class: "icon-lightning", title: "Ship faster", desc: "Articles in minutes" },
        { class: "icon-shield", title: "SEO-strong", desc: "Built around Google intent" },
        { class: "icon-growth", title: "Corporate web assets", desc: "Grow owned-media equity" }
      ]
    else
      [
        { class: "icon-lightning", title: "制作スピード向上", desc: "最短数分で記事完成" },
        { class: "icon-shield", title: "SEOに強い", desc: "Googleに準ずる設計" },
        { class: "icon-growth", title: "企業のWeb資産化", desc: "オウンドメディアを増量" }
      ]
    end
  end

  def lp_problems
    if lp_english?
      [
        { icon_class: "icon-clock", icon_type: "clock", text: "In-house writing eats<br>marketing bandwidth", desc: "Planning, outlining, drafting, and editing crowd out campaigns and core growth work." },
        { icon_class: "icon-search", icon_type: "search", text: "Hard to keep SEO quality<br>at the volume you need", desc: "You need rankings, but keyword design and structure don’t scale across the team." },
        { icon_class: "icon-chart", icon_type: "chart", text: "Quality varies by writer<br>and brand trust suffers", desc: "Freelancer and agency variance weakens consistency across owned media." },
        { icon_class: "icon-analytics", icon_type: "analytics", text: "Traffic and leads stall with<br>no clear content next step", desc: "Analysis and iteration never get enough time — content PDCA does not turn." },
        { icon_class: "icon-calc", icon_type: "calc", text: "Outsourcing costs keep rising<br>while publish volume stays flat", desc: "Writer and editor fees stack up without a path to sustainable in-house scale." },
        { icon_class: "icon-bell", icon_type: "bell", text: "Competitors publish more SEO<br>content and pull ahead", desc: "Keeping pillar/cluster coverage fresh is tough when capacity is limited." }
      ]
    else
      [
        { icon_class: "icon-clock", icon_type: "clock", text: "記事制作がマーケ業務を圧迫し、<br>本来の施策に手が回らない", desc: "企画・構成・執筆・編集の工数が大きく、キャンペーンや本業の成長施策を圧迫している。" },
        { icon_class: "icon-search", icon_type: "search", text: "必要な記事量に対して、<br>SEO品質を維持できない", desc: "検索上位を狙いたいが、キーワード設計や構成づくりがチーム内でスケールしない。" },
        { icon_class: "icon-chart", icon_type: "chart", text: "ライターごとに品質がばらつき、<br>ブランド信頼が落ちる", desc: "外注・代理店ごとの差が出てしまい、オウンドメディア全体の一貫性が損なわれる。" },
        { icon_class: "icon-analytics", icon_type: "analytics", text: "流入・リードが伸び悩み、<br>次のコンテンツ打ち手が見えない", desc: "分析と改善に時間が取れず、コンテンツのPDCAが回せていない。" },
        { icon_class: "icon-calc", icon_type: "calc", text: "外注費は増えるのに、<br>公開本数が伸びない", desc: "ライター・編集への依頼コストが積み重なり、内製での増量に切り替えられない。" },
        { icon_class: "icon-bell", icon_type: "bell", text: "競合がSEO記事を増やし、<br>差をつけられていく", desc: "ピラー／クラスターの網羅と鮮度を保つ余裕がなく、競合オウンドメディアに先行される。" }
      ]
    end
  end

  def lp_concepts
    if lp_english?
      [
        { num: "01", title: "Pillar–cluster structure", desc: "A parent pillar plus child clusters that comprehensively cover the topic.", img: "icon1.png" },
        { num: "02", title: "E-E-A-T ready", desc: "High-precision content that meets experience, expertise, authority, and trust.", img: "icon2.png" },
        { num: "03", title: "User first", desc: "Not just promotion — articles that solve real reader problems for your theme.", img: "icon3.png" }
      ]
    else
      [
        { num: "01", title: "ピラー・クラスター構造", desc: "ピラー記事（親）とそれを網羅するクラスター記事（子）の網羅的な記事構成。", img: "icon1.png" },
        { num: "02", title: "E-E-A-Tへの適応", desc: "経験・専門性・権威性・信頼性を満たした高精度なコンテンツ。", img: "icon2.png" },
        { num: "03", title: "ユーザーファースト", desc: "単なる宣伝ではなく、サイトテーマに準じた読者の課題を解決する役立つ記事。", img: "icon3.png" }
      ]
    end
  end

  def lp_ea_steps
    if lp_english?
      [
        { num: "01", title: "Set genre & theme", desc: "Define the topic area once. The agent uses it as the brief.", icon: "target" },
        { num: "02", title: "Design & write pillars", desc: "AI proposes SEO-strong parent titles and generates the bodies.", icon: "pen" },
        { num: "03", title: "Expand to clusters", desc: "Related child titles and drafts fill out comprehensive coverage.", icon: "layers" },
        { num: "04", title: "Notify when done", desc: "Email/SMS alerts — even if the browser is closed.", icon: "bell" }
      ]
    else
      [
        { num: "01", title: "ジャンル・テーマを設定", desc: "扱う領域を一度定義。以降の生成の指針になります。", icon: "target" },
        { num: "02", title: "ピラーを設計・生成", desc: "検索意図に沿った親タイトルを提案し、本文まで自動で書き上げます。", icon: "pen" },
        { num: "03", title: "クラスターへ展開", desc: "関連する子タイトル・本文まで一連で網羅的に生成します。", icon: "layers" },
        { num: "04", title: "完了を通知", desc: "ブラウザを閉じても進行。完了はメール／SMSで知らせます。", icon: "bell" }
      ]
    end
  end

  def lp_ea_auto_pills
    if lp_english?
      [
        { icon: "zap", text: "End-to-end automation" },
        { icon: "cpu", text: "Runs in the background" },
        { icon: "mail", text: "Email / SMS alerts" }
      ]
    else
      [
        { icon: "zap", text: "一連を自動で実行" },
        { icon: "cpu", text: "バックグラウンド進行" },
        { icon: "mail", text: "メール／SMSで完了通知" }
      ]
    end
  end

  def lp_feature_cards
    if lp_english?
      [
        {
          num: "01", title: "AI target definition", desc: "AI refines ideal audience profiles so marketing teams can set precise targeting quickly.",
          mock_header: "Keyword ideas",
          kw_head: %w[Keyword Competition],
          kw_rows: [
            { kw: "AI article generation", vol: "12,100", b_class: "low", b_text: "Low" },
            { kw: "SEO strategy", vol: "8,900", b_class: "mid", b_text: "Mid" },
            { kw: "Content marketing", vol: "6,600", b_class: "low", b_text: "Low" }
          ]
        },
        {
          num: "02", title: "Auto pillar title ideas", desc: "AI builds SEO-strong, intent-aligned title structures automatically.",
          mock_header: "Outline",
          headings: [
            "What is an AI article tool?",
            "Benefits of AI article tools",
            "Recommended AI writing tools",
            "How to choose one",
            "Summary"
          ]
        },
        {
          num: "03", title: "Auto body writing", desc: "Natural prose from AI — high-quality corporate articles at volume, faster.",
          editor_p1: "AI writing tools cut production time dramatically while helping teams ship higher-quality content at scale.",
          editor_p2: "This guide covers the strengths, benefits, and selection tips for AI article generators."
        },
        {
          num: "04", title: "Auto image generation", desc: "AI generates and suggests images and eye-catchers that match the article."
        },
        {
          num: "05", title: "Cluster titles & drafts", desc: "From a parent title, AI proposes ~15 child titles to scale comprehensive coverage.",
          mock_header: "Improvement tips",
          suggestions: [
            "Including keywords in headings works well",
            "A more concrete intro can lower bounce rate",
            "We recommend adding internal links"
          ]
        },
        {
          num: "06", title: "Publish & integrate", desc: "One-click WordPress publishing that fits in-house editorial workflows.",
          wp_text: "Connecting to WordPress..."
        }
      ]
    else
      [
        {
          num: "01", title: "AIターゲット定義", desc: "AIが理想顧客・読者像を詳細化するので、マーケチームが的確な定義設計を素早く進められます。",
          mock_header: "キーワード候補",
          kw_head: %w[キーワード 競合性],
          kw_rows: [
            { kw: "AI 記事生成", vol: "12,100", b_class: "low", b_text: "低" },
            { kw: "SEO対策", vol: "8,900", b_class: "mid", b_text: "中" },
            { kw: "コンテンツマーケティング", vol: "6,600", b_class: "low", b_text: "低" }
          ]
        },
        {
          num: "02", title: "ピラータイトルの自動提案", desc: "SEOに強く、検索意図に沿ったタイトル構成をAIが自動で作成。",
          mock_header: "構成案",
          headings: %w[AI記事生成ツールとは？ AI記事生成ツールを使うメリット おすすめのAI記事生成ツール 選び方のポイント まとめ]
        },
        {
          num: "03", title: "本文の自動生成", desc: "自然な文章をAIが生成。法人サイト向けの高品質な記事を短時間で量産。",
          editor_p1: "AI記事生成ツールは、記事制作の工数を大幅に削減し、高品質なコンテンツを効率的に作成できるツールです。",
          editor_p2: "本記事では、AI記事生成ツールの特徴やメリット、選び方のポイントを詳しく解説します。"
        },
        {
          num: "04", title: "画像の自動生成", desc: "記事内容に合った画像やアイキャッチをAIが自動で生成・提案。"
        },
        {
          num: "05", title: "クラスタータイトル・記事の自動提案・作成", desc: "親タイトル・記事から最適な構成になる子タイトルを平均15個自動で提案し、網羅的な増量を支援。",
          mock_header: "改善提案",
          suggestions: %w[見出しにキーワードを含めると効果的です 導入文をより具体的にすると離脱率が下がります 内部リンクの追加をおすすめします]
        },
        {
          num: "06", title: "公開・連携", desc: "WordPress連携でワンクリック公開。社内の入稿・運用フローに組み込みやすい。",
          wp_text: "WordPressに接続中..."
        }
      ]
    end
  end

  def lp_fsb_points
    if lp_english?
      [
        { icon_type: "clock", text: "Cut production time for teams" },
        { icon_type: "trend", text: "Scale SEO publish volume" },
        { icon_type: "shield", text: "Stable quality across writers" },
        { icon_type: "Update", text: "Keep corporate content fresh" }
      ]
    else
      [
        { icon_type: "clock", text: "チームの制作時間を大幅カット" },
        { icon_type: "trend", text: "SEO記事の公開本数を増量" },
        { icon_type: "shield", text: "品質を揃えながら安定運用" },
        { icon_type: "Update", text: "企業コンテンツの鮮度を維持" }
      ]
    end
  end

  def lp_dashboard_features
    if lp_english?
      [
        { class: "icon-blue", type: "pie", label: "Key metrics in real time", desc: "See total generations, published, drafts, and success rate at a glance." },
        { class: "icon-amber", type: "folder", label: "Genre-level article status", desc: "Totals and Pillar / Cluster breakdowns to refine content strategy." },
        { class: "icon-indigo", type: "filter", label: "Filter by status instantly", desc: "Switch statuses in one click and find the articles you need." },
        { class: "icon-purple", type: "clock", label: "Live generation progress", desc: "Track AI generation as it happens — completions and progress included." }
      ]
    else
      [
        { class: "icon-blue", type: "pie", label: "重要指標をリアルタイムで把握", desc: "総生成数・公開済・下書き・成功率など、主要な情報をひと目で確認できます。" },
        { class: "icon-amber", type: "folder", label: "ジャンルごとの記事状況を可視化", desc: "ジャンル別の記事総数と、Pillar / Clusterの内訳を確認。コンテンツ戦略の最適化に役立ちます。" },
        { class: "icon-indigo", type: "filter", label: "ステータスごとに簡単フィルタ", desc: "すべてのステータスをワンクリックで切り替え、必要な記事をすぐに検索・管理できます。" },
        { class: "icon-purple", type: "clock", label: "リアルタイム生成状況を確認", desc: "AI生成の進行状況をリアルタイムで確認。完了数や進捗をすぐに把握できます。" }
      ]
    end
  end

  def lp_voices
    if lp_english?
      [
        {
          avatar_class: "avatar-blogger", badge_class: "badge-blue", badge_text: "In-house SEO",
          name: "In-house marketing lead", stars: "★★★★★", rating: "5.0",
          quote: "“In-house article time dropped by more than half!”",
          body: "From keyword research to outlines and drafts, we internalized the full flow. Cycle time shrank and internal alignment sped up.",
          metrics: [
            { type: "clock", label: "Production effort", val_class: "val-down", val: "-60%" },
            { type: "trend", label: "Organic traffic", val_class: "val-up", val: "+210%" }
          ],
          footer: "Change in 3 months"
        },
        {
          avatar_class: "avatar-editor", badge_class: "badge-cyan", badge_text: "Editorial studio",
          name: "Agency director", stars: "★★★★★", rating: "5.0",
          quote: "“Writer QC and rewrites became dramatically smoother.”",
          body: "Quality varied by writer. Drafity’s outlines and rewrite suggestions let us ship consistent, high-quality content at volume.",
          metrics: [
            { type: "shield", label: "Edit / proof time", val_class: "val-down", val: "-45%" },
            { type: "chart", label: "Monthly deliveries", val_class: "val-up", val: "+180%" }
          ],
          footer: "Change in 6 months"
        },
        {
          avatar_class: "avatar-manager", badge_class: "badge-indigo", badge_text: "B2B marketing",
          name: "Owned-media lead", stars: "★★★★★", rating: "5.0",
          quote: "“Target keywords climbed — and CV followed.”",
          body: "Competitive analysis and live SEO scoring are excellent. More top rankings on strategic keywords drove stronger leads.",
          metrics: [
            { type: "team", label: "Leads won", val_class: "val-up", val: "+250%" },
            { type: "search", label: "Top-rank KWs", val_class: "val-up", val: "+145%" }
          ],
          footer: "Change in 4 months"
        },
        {
          avatar_class: "avatar-marketer", badge_class: "badge-orange", badge_text: "SaaS company",
          name: "Content marketing lead (CMO)", stars: "★★★★★", rating: "5.0",
          quote: "“We cut external writing spend significantly!”",
          body: "With AI support, specialized docs stay in-house. We reduced freelance spend while publishing more original, expert content.",
          metrics: [
            { type: "tool", label: "Outsource cost", val_class: "val-down", val: "-50%" },
            { type: "write", label: "Articles published", val_class: "val-up", val: "+160%" }
          ],
          footer: "Change in 5 months"
        }
      ]
    else
      [
        {
          avatar_class: "avatar-blogger", badge_class: "badge-blue", badge_text: "インハウスSEO",
          name: "事業会社 マーケティング担当者", stars: "★★★★★", rating: "5.0",
          quote: "「インハウスでの記事作成時間が半分以下になりました！」",
          body: "キーワード調査から構成案、本文作成まで一気通貫で内製化できるため、記事制作の時間が大幅に短縮。社内調整もスムーズになり、検証スピードが向上しました。",
          metrics: [
            { type: "clock", label: "作成工数", val_class: "val-down", val: "-60%" },
            { type: "trend", label: "自然検索流入", val_class: "val-up", val: "+210%" }
          ],
          footer: "導入から3ヶ月の変化"
        },
        {
          avatar_class: "avatar-editor", badge_class: "badge-cyan", badge_text: "編集プロダクション",
          name: "受託制作 ディレクター", stars: "★★★★★", rating: "5.0",
          quote: "「外注ライターの品質管理とリライトが極めてスムーズに。」",
          body: "ライターごとに品質のばらつきがあるのが大きな課題でしたが、Drafityの構成案と校正・リライト提案機能により、均一で高品質なコンテンツを安定量産できています。",
          metrics: [
            { type: "shield", label: "編集・校正時間", val_class: "val-down", val: "-45%" },
            { type: "chart", label: "月間納品本数", val_class: "val-up", val: "+180%" }
          ],
          footer: "導入から6ヶ月の変化"
        },
        {
          avatar_class: "avatar-manager", badge_class: "badge-indigo", badge_text: "B2Bマーケティング",
          name: "オウンドメディア運営責任者", stars: "★★★★★", rating: "5.0",
          quote: "「狙った重点キーワードで上位獲得。CV増加に直結！」",
          body: "競合分析やリアルタイムのSEOスコア機能が極めて優秀です。狙いすました戦略的キーワードで検索上位表示が増え、質の高いホワイトペーパーDLや問い合わせに繋がっています。",
          metrics: [
            { type: "team", label: "獲得リード数", val_class: "val-up", val: "+250%" },
            { type: "search", label: "上位表示KW数", val_class: "val-up", val: "+145%" }
          ],
          footer: "導入から4ヶ月の変化"
        },
        {
          avatar_class: "avatar-marketer", badge_class: "badge-orange", badge_text: "SaaS運営企業",
          name: "コンテンツマーケ責任者（CMO）", stars: "★★★★★", rating: "5.0",
          quote: "「外部の執筆外注コストを大幅に削減できました！」",
          body: "AIアシスタントのサポートにより、専門知識のドキュメント化がチーム内で完結。外部のライティング外注費用を大きく抑えつつ、より専門性の高い独自性の強い一次情報記事を発信できています。",
          metrics: [
            { type: "tool", label: "外注コスト", val_class: "val-down", val: "-50%" },
            { type: "write", label: "公開記事本数", val_class: "val-up", val: "+160%" }
          ],
          footer: "導入から5ヶ月の変化"
        }
      ]
    end
  end

  def lp_industry_tags
    if lp_english?
      [
        { icon: "💻", name: "B2B / SaaS owned media" },
        { icon: "🏢", name: "Corporate marketing sites" },
        { icon: "🛒", name: "EC & retail content" },
        { icon: "📈", name: "Finance & real estate" },
        { icon: "🏥", name: "Healthcare & education" },
        { icon: "📰", name: "Agency / content ops" }
      ]
    else
      [
        { icon: "💻", name: "B2B・SaaSオウンドメディア" },
        { icon: "🏢", name: "事業会社のコーポレート" },
        { icon: "🛒", name: "EC・小売コンテンツ" },
        { icon: "📈", name: "金融・不動産" },
        { icon: "🏥", name: "医療・教育" },
        { icon: "📰", name: "制作会社・運用代行" }
      ]
    end
  end

  def lp_trial_features
    if lp_english?
      [
        { icon: "polyline", label: "Start free", desc: "Try article generation, SEO analysis, image gen, and more" },
        { icon: "calendar", label: "Commercial use OK", desc: "Trial articles are yours for business use" },
        { icon: "shield", label: "Cancel anytime", desc: "Cancel during the trial and you pay nothing" }
      ]
    else
      [
        { icon: "polyline", label: "まずは無料で検証", desc: "記事生成・SEO分析・画像生成など、法人導入前に主要機能を体験" },
        { icon: "calendar", label: "商用利用OK", desc: "トライアル期間でも作成記事はそのまま業務利用できます" },
        { icon: "shield", label: "いつでも解約可能", desc: "トライアル期間中に解約すれば料金は一切かかりません" }
      ]
    end
  end

  FAQ_CATEGORIES = [
    ["service", "サービスについて", "comments"],
    ["pricing", "料金・トライアル", "yen"],
    ["setup", "申し込み・開始", "rocket"],
    ["usage", "使い方・運用", "chart"]
  ].freeze

  FAQ_CATEGORIES_EN = [
    ["service", "Service", "comments"],
    ["pricing", "Pricing & trial", "yen"],
    ["setup", "Signup & launch", "rocket"],
    ["usage", "Usage", "chart"]
  ].freeze

  FAQ_ITEMS = [
    # service
    { category: "service", q: "Drafityはどんなサービスですか？", a: "法人のオウンドメディア・コンテンツマーケ向けに、SEO構成から本文・画像・リライト・効果測定までを一つの画面で進めるAIコンテンツ増量プラットフォームです。親記事（ピラー）と子記事（クラスター）の設計にも対応しています。" },
    { category: "service", q: "SEOスコアはどう出ますか？", a: "見出し構成やキーワード比率などをもとに、AIが100点満点で自動査定します。生成後にエディタで直しながらスコアを確認できます。" },
    { category: "service", q: "記事生成中にブラウザを閉じても大丈夫ですか？", a: "はい。サーバー側で処理が続くため、画面を閉じても生成は止まりません。" },
    { category: "service", q: "WordPressやAPI連携はできますか？", a: "はい。WordPressへのワンクリック公開やCMS向けエクスポートに対応しています。API利用はスターター以上です（トライアルでは不可）。" },
    { category: "service", q: "生成した記事の著作権は誰のものですか？", a: "トライアル期間を含め、生成した記事はお客様のコンテンツとしてご利用いただけます。" },

    # pricing
    { category: "pricing", q: "無料トライアルの条件は？", a: "#{Subscription::TRIAL_DAYS}日間・0円です。上限は親記事1・子記事3・画像5・タイトル提案1。アカウント登録だけで開始でき、クレジットカードは不要です。期間終了後はスタンダード（月額49,800円）へ移行します。" },
    { category: "pricing", q: "料金プランと記事上限は？", a: "スターター月額29,800円（親3・子45）／スタンダード49,800円（5・75）／ビジネス98,000円（15・225、AI自律あり）／エンタープライズ198,000円（50・750）。年額払いは月額換算で約20%お得です。詳細は料金セクションをご確認ください。" },
    { category: "pricing", q: "トライアル中に解約したら課金されますか？", a: "トライアル期間中に解約すれば料金はかかりません。解約後も契約期間の終了日までは利用できます。" },
    { category: "pricing", q: "プラン変更や請求書払いはできますか？", a: "プラン変更はダッシュボードの契約管理から可能です。請求書払いは契約形態により案内します。法人でのご利用・請求書払いをご希望の場合はお問い合わせください。" },

    # setup
    { category: "setup", q: "申し込みから最初の記事までの手順は？", a: "①「無料で始める」からアカウント登録→②登録完了と同時にトライアル開始（カード不要）→③料金プラン画面で現状確認／必要なら有料プランへCheckout→④キーワード入力から構成・本文を生成→⑤エディタで編集し、公開またはWordPress連携、の順です。最短数分で下書きまで進められます。" },
    { category: "setup", q: "始めるときに用意するものは？", a: "特別な準備は不要です。狙いたいキーワードやテーマが決まっていればすぐ生成できます。プログラミング知識も不要です。" },
    { category: "setup", q: "有料プランへの切り替え方は？", a: "ダッシュボードの料金プラン（/plans）からプランと月額／年額を選び、クレジットカードでCheckoutします。エンタープライズは問い合わせ導線もあります。" },

    # usage
    { category: "usage", q: "既存記事のリライトはできますか？", a: "はい。既存コンテンツのSEO改善・リライトに対応し、スコアを見ながら直せます。" },
    { category: "usage", q: "複数メディアを1アカウントで運用できますか？", a: "はい。プランに応じて複数プロジェクトを管理でき、マーケ・SEOチームでの共同運用にも対応しています。" },
    { category: "usage", q: "AI自律生成はどのプランからですか？", a: "ビジネスおよびエンタープライズです。スターター・スタンダードには含まれません。" }
  ].freeze

  FAQ_ITEMS_EN = [
    # service
    { category: "service", q: "What is Drafity?", a: "An AI content-volume platform for corporate owned media and content marketing—SEO outlines, article generation, images, rewrites, and measurement in one place, including pillar/cluster structures." },
    { category: "service", q: "How is the SEO score calculated?", a: "AI scores headings, keyword balance, and more out of 100. Edit in the editor while watching the score." },
    { category: "service", q: "Can I close the browser while generating?", a: "Yes. Generation continues server-side even if you leave the page." },
    { category: "service", q: "Does it support WordPress and API?", a: "Yes—one-click WordPress publish and CMS export. API is available on Starter and above (not on Trial)." },
    { category: "service", q: "Who owns generated content?", a: "Articles you generate—including during the trial—are yours to use." },

    # pricing
    { category: "pricing", q: "What are the free trial terms?", a: "#{Subscription::TRIAL_DAYS} days at ¥0: 1 parent article, 3 child articles, 5 images, 1 title suggestion. No card needed to start. After the trial you move to Standard (¥49,800/month)." },
    { category: "pricing", q: "What are the plans and article limits?", a: "Starter ¥29,800/mo (3 parent / 45 child) / Standard ¥49,800 (5 / 75) / Business ¥98,000 (15 / 225, AI autonomous) / Enterprise ¥198,000 (50 / 750). Yearly billing is about 20% off vs monthly. See the pricing section." },
    { category: "pricing", q: "If I cancel during the trial, am I charged?", a: "No. Cancel during the trial and you pay nothing. You can keep using until the current period ends." },
    { category: "pricing", q: "Can I change plans or pay by invoice?", a: "Yes—change plans from dashboard billing. Invoice payment depends on contract type; contact us for company billing." },

    # setup
    { category: "setup", q: "What are the steps from signup to first article?", a: "1) Sign up via Free start → 2) Trial begins immediately (no card) → 3) Review /plans and upgrade via Checkout if needed → 4) Enter keywords to generate outline and body → 5) Edit, then publish or push to WordPress. First draft often takes only a few minutes." },
    { category: "setup", q: "What do I need to prepare?", a: "Nothing special—just target keywords or themes. No coding skills required." },
    { category: "setup", q: "How do I switch to a paid plan?", a: "Choose monthly or yearly on /plans and complete Stripe Checkout. Enterprise also has a contact CTA." },

    # usage
    { category: "usage", q: "Can I rewrite existing articles?", a: "Yes. Improve SEO and rewrite while watching the score." },
    { category: "usage", q: "Can one account run multiple media sites?", a: "Yes. Depending on your plan, manage multiple projects and collaborate with marketing and SEO teams." },
    { category: "usage", q: "Which plans include AI autonomous generation?", a: "Business and Enterprise only—not Starter or Standard." }
  ].freeze

  def lp_faq_categories
    lp_english? ? FAQ_CATEGORIES_EN : FAQ_CATEGORIES
  end

  def lp_faqs
    lp_english? ? FAQ_ITEMS_EN : FAQ_ITEMS
  end

  def lp_about_stats
    if lp_english?
      [
        { type: "shop", label: "Customer satisfaction", num: "97.5", unit: "%" },
        { type: "team", label: "Adopting companies", num: "500", unit: "+" },
        { type: "doc", label: "Articles generated", num: "10k", unit: "+" }
      ]
    else
      [
        { type: "shop", label: "顧客満足度", num: "97.5", unit: "%" },
        { type: "team", label: "累計導入社数", num: "500", unit: "+社" },
        { type: "doc", label: "累計生成記事数", num: "1", unit: "万記事+" }
      ]
    end
  end

  def lp_about_rows
    if lp_english?
      [
        { th: "Company", td: "J Work Inc.", html: false },
        { th: "Address", td: "2F, 2-2-15 Hamamatsucho, Minato-ku, Tokyo 105-0013, Japan", html: true },
        { th: "Founded", td: "August 2024", html: false },
        { th: "Representative", td: "Taro Yamada", html: false },
        { th: "Business", td: "Development of AI article SaaS “Drafity”<br>Media & content marketing support", html: true },
        { th: "Capital", td: "¥5,000,000", html: false }
      ]
    else
      [
        { th: "会社名", td: "合同会社ファクトル", html: false },
        { th: "所在地", td: "熊本県天草市中央新町12-13", html: true },
        { th: "設立", td: "2022年1月", html: false },
        { th: "代表者", td: "奥山　健太", html: false },
        { th: "事業内容", td: "AI記事生成SaaS「Drafity」の開発・提供<br>メディア支援・コンテンツマーケティング支援", html: true },
        { th: "資本金", td: "100万円", html: false }
      ]
    end
  end
end
