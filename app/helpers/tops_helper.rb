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
      next unless column.genre.to_s == CrawlPolicy::GENRE_KEY

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
        { class: "icon-lightning", title: "Extremely fast", desc: "Articles in minutes" },
        { class: "icon-shield", title: "SEO-strong", desc: "Built around Google intent" },
        { class: "icon-growth", title: "Asset content", desc: "Grow your web equity" }
      ]
    else
      [
        { class: "icon-lightning", title: "圧倒的に速い", desc: "最短数分で記事完成" },
        { class: "icon-shield", title: "SEOに強い", desc: "Googleに準ずる設計" },
        { class: "icon-growth", title: "資産コンテンツ化", desc: "企業のWeb資産へ" }
      ]
    end
  end

  def lp_problems
    if lp_english?
      [
        { icon_class: "icon-clock", icon_type: "clock", text: "Writing takes too long and<br>pulls focus from core work", desc: "Planning, outlining, drafting, and editing eat into day-to-day operations." },
        { icon_class: "icon-search", icon_type: "search", text: "SEO-minded articles<br>are hard to write well", desc: "You want rankings, but keyword design and structure are tough — results stall." },
        { icon_class: "icon-chart", icon_type: "chart", text: "Quality is inconsistent and<br>readers are not satisfied", desc: "Writer-to-writer variance hurts trust across the whole media brand." },
        { icon_class: "icon-analytics", icon_type: "analytics", text: "Traffic and outcomes stall with<br>no clear next move", desc: "Analysis and iteration never get enough time — PDCA does not turn." },
        { icon_class: "icon-calc", icon_type: "calc", text: "Outsourcing costs keep rising<br>and margin shrinks", desc: "Writer and editor fees stack up and squeeze profit." },
        { icon_class: "icon-bell", icon_type: "bell", text: "Hard to track Google’s SEO structure correctly", desc: "Keeping content fresh is tough and competitors pull ahead." }
      ]
    else
      [
        { icon_class: "icon-clock", icon_type: "clock", text: "記事制作に時間がかかり、<br>本来の業務に集中できない", desc: "企画・構成・執筆・編集などの工数が大きく、日々の運営業務を圧迫している。" },
        { icon_class: "icon-search", icon_type: "search", text: "SEOを意識した記事が<br>うまく書けない", desc: "検索上位を狙いたいが、キーワード設計や構成づくりが難しく、成果につながらない。" },
        { icon_class: "icon-chart", icon_type: "chart", text: "記事の品質にばらつきがあり、<br>読者の満足度が上がらない", desc: "ライターによってクオリティに差が出てしまい、メディア全体の信頼性に影響してしまう。" },
        { icon_class: "icon-analytics", icon_type: "analytics", text: "アクセスや成果が伸び悩み、<br>改善の打ち手が見えない", desc: "データ分析や改善施策に時間が取れず、PDCAが回せていない。" },
        { icon_class: "icon-calc", icon_type: "calc", text: "外注コストがかさみ、<br>運営コストが増大している", desc: "ライターや編集者への依頼コストが積み重なり、利益を圧迫している。" },
        { icon_class: "icon-bell", icon_type: "bell", text: "GoogleのSEO構成を正しく把握できない", desc: "情報の鮮度を保つのが難しく、競合メディアに差をつけられてしまう。" }
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

  def lp_feature_cards
    if lp_english?
      [
        {
          num: "01", title: "AI target definition", desc: "AI refines your ideal audience so you can set precise targeting with ease.",
          mock_header: "Keyword ideas",
          kw_head: %w[Keyword Competition],
          kw_rows: [
            { kw: "AI article generation", vol: "12,100", b_class: "low", b_text: "Low" },
            { kw: "SEO strategy", vol: "8,900", b_class: "mid", b_text: "Mid" },
            { kw: "Content marketing", vol: "6,600", b_class: "low", b_text: "Low" }
          ]
        },
        {
          num: "02", title: "Auto pillar title ideas", desc: "AI builds SEO-strong, high-intent title structures automatically.",
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
          num: "03", title: "Auto body writing", desc: "Natural prose from AI — high-quality articles in less time.",
          editor_p1: "AI writing tools cut production time dramatically while helping teams ship higher-quality content at scale.",
          editor_p2: "This guide covers the strengths, benefits, and selection tips for AI article generators."
        },
        {
          num: "04", title: "Auto image generation", desc: "AI generates and suggests images and eye-catchers that match the article."
        },
        {
          num: "05", title: "Cluster titles & drafts", desc: "From a parent title, AI proposes ~15 child titles for an optimal structure.",
          mock_header: "Improvement tips",
          suggestions: [
            "Including keywords in headings works well",
            "A more concrete intro can lower bounce rate",
            "We recommend adding internal links"
          ]
        },
        {
          num: "06", title: "Publish & integrate", desc: "One-click WordPress publishing for a smooth editorial workflow.",
          wp_text: "Connecting to WordPress..."
        }
      ]
    else
      [
        {
          num: "01", title: "AIターゲット定義", desc: "AIがあなたの希望のターゲット選定を詳細化するので、手軽に的確な定義設計ができます。",
          mock_header: "キーワード候補",
          kw_head: %w[キーワード 競合性],
          kw_rows: [
            { kw: "AI 記事生成", vol: "12,100", b_class: "low", b_text: "低" },
            { kw: "SEO対策", vol: "8,900", b_class: "mid", b_text: "中" },
            { kw: "コンテンツマーケティング", vol: "6,600", b_class: "low", b_text: "低" }
          ]
        },
        {
          num: "02", title: "ピラータイトルの自動提案", desc: "SEOに強くユーザービューイングの高いタイトル構成をAIが自動で作成。",
          mock_header: "構成案",
          headings: %w[AI記事生成ツールとは？ AI記事生成ツールを使うメリット おすすめのAI記事生成ツール 選び方のポイント まとめ]
        },
        {
          num: "03", title: "本文の自動生成", desc: "自然な文章をAIが生成。高品質な記事を短時間で作成。",
          editor_p1: "AI記事生成ツールは、記事制作の工数を大幅に削減し、高品質なコンテンツを効率的に作成できるツールです。",
          editor_p2: "本記事では、AI記事生成ツールの特徴やメリット、選び方のポイントを詳しく解説します。"
        },
        {
          num: "04", title: "画像の自動生成", desc: "記事内容に合った画像やアイキャッチをAIが自動で生成・提案。"
        },
        {
          num: "05", title: "クラスタータイトル・記事の自動提案・作成", desc: "親タイトル・記事から最適な構成になる子タイトルを平均15個自動で提案します。",
          mock_header: "改善提案",
          suggestions: %w[見出しにキーワードを含めると効果的です 導入文をより具体的にすると離脱率が下がります 内部リンクの追加をおすすめします]
        },
        {
          num: "06", title: "公開・連携", desc: "WordPress連携でワンクリック公開。スムーズに入稿・運用が可能。",
          wp_text: "WordPressに接続中..."
        }
      ]
    end
  end

  def lp_fsb_points
    if lp_english?
      [
        { icon_type: "clock", text: "Slash production time" },
        { icon_type: "trend", text: "Maximize SEO results" },
        { icon_type: "shield", text: "Stable ops without quality loss" },
        { icon_type: "Update", text: "Regular updates that raise accuracy" }
      ]
    else
      [
        { icon_type: "clock", text: "制作時間を大幅カット" },
        { icon_type: "trend", text: "SEO成果を最大化" },
        { icon_type: "shield", text: "品質を保ちながら安定運用" },
        { icon_type: "Update", text: "常に記事精度を上げる定期更新" }
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
        { icon: "📝", name: "Blogs & affiliate" },
        { icon: "📰", name: "News media" },
        { icon: "💻", name: "Owned media" },
        { icon: "🛒", name: "EC & comparison" },
        { icon: "📈", name: "Finance & real estate" },
        { icon: "🔍", name: "SaaS & IT media" }
      ]
    else
      [
        { icon: "📝", name: "ブログ・アフィリエイト" },
        { icon: "📰", name: "ニュースメディア" },
        { icon: "💻", name: "オウンドメディア" },
        { icon: "🛒", name: "EC・比較メディア" },
        { icon: "📈", name: "金融・不動産メディア" },
        { icon: "🔍", name: "SaaS・ITメディア" }
      ]
    end
  end

  def lp_trial_features
    if lp_english?
      [
        { icon: "polyline", label: "Start free", desc: "Try article generation, SEO analysis, image gen, and more" },
        { icon: "calendar", label: "Commercial use OK", desc: "Articles made in the trial remain yours to use" },
        { icon: "shield", label: "Cancel anytime", desc: "Cancel during the trial and you pay nothing" }
      ]
    else
      [
        { icon: "polyline", label: "まずは無料体験", desc: "記事生成・SEO分析・画像生成など主要機能をお試しいただけます" },
        { icon: "calendar", label: "商用利用OK", desc: "トライアル期間でも作成いただいた記事はそのままご利用いただけます" },
        { icon: "shield", label: "いつでも解約可能", desc: "トライアル期間中に解約すれば料金は一切かかりません" }
      ]
    end
  end

  def lp_faqs
    if lp_english?
      [
        { q: "Is the free plan really free?", a: "Yes. You can use 1 parent article and 3 child articles for free, forever." },
        { q: "How is the SEO score calculated?", a: "AI analyzes ranking tendencies across headings, keyword balance, and more — scoring out of 100 automatically." },
        { q: "Can I close the browser while generating?", a: "Yes. Generation runs server-side in the background, so work continues even if you leave the page." },
        { q: "Does it integrate with WordPress and other tools?", a: "Yes. API and CMS export options let you publish optimized articles to your site smoothly." }
      ]
    else
      [
        { q: "無料プランは本当に無料ですか？", a: "はい。親記事1記事・子記事3記事まで無料でずっとご利用いただけます。" },
        { q: "SEOスコアはどのように計測されますか？", a: "Googleの上位表示アルゴリズムの傾向をAIが独自に多角分析し、見出し構成やキーワード比率などから100点満点で客観的に自動査定します。" },
        { q: "記事生成中にブラウザを閉じても大丈夫ですか？", a: "はい、完全に問題ありません。バックグラウンドのサーバーサイドですべて自動進行・生成されるため、画面を閉じた状態でも処理は継続されます。" },
        { q: "他のツールやWordPressとの連携はできますか？", a: "はい、API連携やCMS向けのエクスポート機能を備えており、生成した最適記事をスムーズに構築サイトへ反映させることができます。" }
      ]
    end
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
