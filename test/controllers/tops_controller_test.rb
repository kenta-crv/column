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

  test "development page explains contract development without blog links" do
    assert_equal "/development", development_path

    get development_path

    assert_response :success
    assert_match "初期費用", response.body
    assert_match ">0<", response.body
    assert_match "月額", response.body
    assert_match "御社専用", response.body
    assert_match "保守", response.body
    assert_match "メンテナンス", response.body
    assert_no_match %r{href="[^"]*columns}, response.body
    assert_no_match "ブログ", response.body
    assert_no_match "無料トライアル", response.body
    assert_no_match "seo-checker", response.body
    assert_match "logo2", response.body
    assert_match "hero-bg", response.body
    assert_match "/assets/whats-", response.body
    assert_match "icon-calc", response.body
    assert_match "features-scroll-next", response.body
    assert_match ">Drafity<", response.body
    assert_match "導入の流れ", response.body
    assert_match "開発してほしい内容", response.body
    assert_match "作りたいシステム", response.body
    assert_no_match "mailto:", response.body
  end

  test "development inquiry stores the request and sends mail" do
    assert_difference "Contract.count", 1 do
      assert_emails 2 do
        post development_inquiry_path, params: {
          inquiry: {
            company: "株式会社例",
            name: "担当",
            email: "dev-inquiry@example.com",
            tel: "03-0000-0000",
            system_type: "社内業務・管理画面",
            audience: "社員",
            situation: "公開中のシステムがある",
            message: "進捗を同じ画面で見たい"
          }
        }
      end
    end

    assert_redirected_to development_path(sent: 1, anchor: "consult")
    contract = Contract.order(:id).last
    assert_equal "社内業務・管理画面", contract.service
    assert_equal "dev-inquiry@example.com", contract.email
    assert_includes contract.message, "進捗を同じ画面で見たい"
    assert_includes contract.message, "作りたいシステム: 社内業務・管理画面"
    assert_includes contract.message, "主な利用者: 社員"
  end

  test "development inquiry rejects a blank form" do
    assert_no_difference "Contract.count" do
      post development_inquiry_path, params: { inquiry: { company: "" } }
    end

    assert_response :unprocessable_entity
    assert_match "会社名 を入力してください", response.body
  end

  test "root page stays the product landing page" do
    get root_path

    assert_response :success
    assert_match "無料トライアル", response.body
    assert_no_match "最適化SEO記事で加速する", response.body
    assert_no_match "한국어", response.body
  end
end
