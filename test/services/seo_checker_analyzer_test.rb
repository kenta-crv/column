# frozen_string_literal: true

require "test_helper"

class SeoCheckerAnalyzerTest < ActiveSupport::TestCase
  test "scores a well structured article page" do
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

    assert result.overall_score >= 60
    assert_equal "コンテンツSEO入門", result.cluster[:pillar_candidate]
    assert_equal "見出しの付け方", result.cluster[:cluster_candidate]
    assert result.cluster[:confidence] >= 50
    assert result.axes[:basic_seo][:score] >= 50
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
    assert result.improvements.any?
  end
end
