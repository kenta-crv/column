require "test_helper"

class TopsControllerTest < ActionDispatch::IntegrationTest
  test "overseas seo page stays in tops and is not the root page" do
    assert_equal "/overseas", overseas_seo_path

    get overseas_seo_path

    assert_response :success
    assert_match "/images/overseas-hero-bg.webp", response.body
    assert_match "/overseas-seo.css", response.body
    assert_match "98,000", response.body
    assert_match "海外SEO", response.body
    assert_match "検索エンジン最適化", response.body
    assert_match "機械翻訳感のない、高品質な現地語原稿の生成", response.body
    assert_no_match "希望国・言語の指定", response.body
    assert_no_match "指定言語での記事生成代行", response.body
    assert_match ">Drafity<", response.body
    assert_match "最適化SEO記事で加速する", response.body
    assert_match "한국어", response.body
    assert_match "中文", response.body
    assert_match "English", response.body
    assert_match "Deutsch", response.body
    assert_match "国が違えば、評価されるSEO基準も大きく異なります", response.body
    assert_match "単なる翻訳ではなく", response.body
    assert_match "制作の流れ", response.body
    assert_match "検索エンジン別 記事骨格の設計", response.body
    assert_no_match "指定いただければ", response.body
    assert_no_match "指定言語", response.body
    assert_no_match "調査して、出して、見て、また書く", response.body
    assert_no_match "ひと続き", response.body
    assert_no_match "キーワード調査", response.body
    assert_no_match "国・言語の指定", response.body
    assert_no_match "無料トライアル", response.body

    get "/overseas-seo"
    assert_redirected_to "/overseas"
  end

  test "root page stays the product landing page" do
    get root_path

    assert_response :success
    assert_match "無料トライアル", response.body
    assert_no_match "最適化SEO記事で加速する", response.body
    assert_no_match "한국어", response.body
  end
end
