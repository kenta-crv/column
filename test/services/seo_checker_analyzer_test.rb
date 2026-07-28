# frozen_string_literal: true

require "test_helper"

class SeoCheckerAnalyzerTest < ActiveSupport::TestCase
  test "scores a well structured article page and detects cluster" do
    html = <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>コンテンツSEO入門｜見出しの付け方と内部リンク設計</title>
          <meta name="description" content="コンテンツSEOにおける見出し設計と内部リンクの具体的な手順を、数値例付きで解説します。">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta property="og:title" content="見出しの付け方">
          <link rel="canonical" href="https://example.com/seo/content-seo/headings">
          <script type="application/ld+json">
            {"@type":"BreadcrumbList","itemListElement":[
              {"@type":"ListItem","position":1,"name":"ホーム"},
              {"@type":"ListItem","position":2,"name":"SEO対策"},
              {"@type":"ListItem","position":3,"name":"コンテンツSEO入門"},
              {"@type":"ListItem","position":4,"name":"見出しの付け方"}
            ]}
          </script>
        </head>
        <body>
          <main>
            <h1>見出しの付け方と内部リンク設計</h1>
            <p>例えば、検索意図に合わせてH2を6つ置くと、滞在時間が20%改善した事例があります。</p>
            <h2>手順1：検索意図を分解する</h2>
            <p>#{'具体的なポイントを詳しく説明します。' * 40}</p>
            <h2>手順2：見出しを設計する</h2>
            <ul><li>H2は4〜8個</li><li>数値を入れる</li></ul>
            <h2>手順3：ピラーへリンクする</h2>
            <p>#{'まとめとして親記事へ誘導します。' * 30}</p>
            <h2>よくある質問</h2>
            <p>#{'FAQの回答を詳しく書きます。' * 20}</p>
            <a href="/seo/content-seo">コンテンツSEO入門</a>
            <a href="/seo/content-seo/internal-links">内部リンク設計</a>
            <a href="https://developers.google.com/search">Google公式</a>
            <img src="/a.jpg" alt="見出し構造の図">
          </main>
        </body>
      </html>
    HTML

    result = SeoChecker::Analyzer.analyze(
      url: "https://example.com/seo/content-seo/headings",
      html: html,
      final_url: "https://example.com/seo/content-seo/headings"
    )

    assert result.overall_score >= 65, "expected >=65 got #{result.overall_score}"
    assert_equal "detected", result.cluster[:status]
    assert_equal "コンテンツSEO入門", result.cluster[:pillar_candidate]
    assert_equal "見出しの付け方", result.cluster[:cluster_candidate]
    assert result.cluster[:confidence] >= 55
    assert result.axes[:basic_seo][:score] >= 50
  end

  test "detects cluster from url path when breadcrumbs missing" do
    html = <<~HTML
      <html><head><title>クラスター記事のタイトルは十分長いです</title>
      <meta name="description" content="説明文は六十文字以上になるように調整したメタディスクリプションです。">
      <meta name="viewport" content="width=device-width"></head>
      <body><main><h1>子記事</h1>
      <h2>A</h2><p>#{'本文です。' * 200}</p>
      <h2>B</h2><p>#{'続きです。' * 200}</p>
      <h2>C</h2><p>#{'さらにです。' * 200}</p>
      <a href="/ai_article/columns">一覧</a>
      </main></body></html>
    HTML

    result = SeoChecker::Analyzer.analyze(
      url: "https://example.com/ai_article/columns/child-slug",
      html: html,
      final_url: "https://example.com/ai_article/columns/child-slug"
    )

    assert_includes %w[detected weak], result.cluster[:status]
    assert result.cluster[:pillar_candidate].present?
    assert result.cluster[:cluster_candidate].present?
    assert result.overall_score >= 55, "expected >=55 got #{result.overall_score}"
  end

  test "flags thin pages with weak cluster signals" do
    html = <<~HTML
      <html><head><title>Hi</title></head>
      <body><h1>Hi</h1><p>短い</p></body></html>
    HTML

    result = SeoChecker::Analyzer.analyze(
      url: "https://example.com/",
      html: html,
      final_url: "https://example.com/"
    )

    assert result.overall_score < 55
    assert_equal "not_applicable", result.cluster[:status]
    assert result.improvements.any?
  end

  test "does not mistake feature card articles for main content" do
    html = <<~HTML
      <html><head>
        <title>AI商談代行サービス Meetia｜24時間365日、AIが音声商談を代行</title>
        <meta name="description" content="Meetiaは24時間365日、AIが音声商談を代行するサービスです。資料解析から商談まで自動化します。">
        <meta name="viewport" content="width=device-width">
      </head><body class="lp-body">
        <div class="modern-lp">
          <h1>AIによる本格商談体験へようこそ</h1>
          <h2>機能一覧</h2>
          <p>#{'サービス説明の本文です。' * 120}</p>
          <h2>料金プラン</h2>
          <p>#{'料金に関する詳しい説明です。' * 100}</p>
          <h2>導入事例</h2>
          <p>#{'導入事例の本文を詳しく書きます。' * 100}</p>
          <article class="feature-card"><h3>カード</h3><p>短い</p></article>
          <table><tr><th>項目</th><td>内容</td></tr></table>
        </div>
      </body></html>
    HTML

    result = SeoChecker::Analyzer.analyze(
      url: "https://meetia.pro/",
      html: html,
      final_url: "https://meetia.pro/"
    )

    assert result.stats[:char_count] > 500, "got #{result.stats[:char_count]}"
    assert result.axes[:content][:score] >= 50
    assert_equal "not_applicable", result.cluster[:status]
    assert result.axes[:cluster][:excluded]
    assert_nil result.axes[:cluster][:score]
    # 総合はクラスター除外の3軸平均
    assert result.overall_score >= 70
  end

  test "counts keyword occurrences and h4 headings" do
    html = <<~HTML
      <html><head>
        <title>コンテンツSEOの基礎とコンテンツSEOの実践</title>
        <meta name="description" content="コンテンツSEOを学ぶ入門記事です。">
      </head><body><main>
        <h1>コンテンツSEO入門</h1>
        <h2>概要</h2>
        <p>コンテンツSEOとは何か。コンテンツSEOのポイントを解説します。</p>
        <h3>詳細</h3>
        <h4>補足</h4>
        <h4>まとめ補足</h4>
      </main></body></html>
    HTML

    result = SeoChecker::Analyzer.analyze(
      url: "https://example.com/seo",
      html: html,
      final_url: "https://example.com/seo",
      keyword: "コンテンツSEO"
    )

    kw = result.stats[:keyword]
    assert kw[:present]
    assert_equal "コンテンツSEO", kw[:keyword]
    assert_equal 2, kw[:title_count]
    assert_equal 1, kw[:heading_count]
    assert_equal 2, kw[:body_count]
    assert_equal 1, kw[:description_count]
    assert_equal 6, kw[:total_count]
    assert_equal 2, result.stats[:h4_count]
  end
end
