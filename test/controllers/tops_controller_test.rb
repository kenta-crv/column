require "test_helper"

class TopsControllerTest < ActionDispatch::IntegrationTest
  test "overseas seo page stays in tops and is not the root page" do
    get overseas_seo_path

    assert_response :success
    assert_match "98,000", response.body
    assert_match "市場調査", response.body
    assert_match "コンサルティング", response.body
    assert_match ">Drafity<", response.body
    assert_match "海外SEOを、", response.body
    assert_match "キーワード調査、記事作成、サイトへの公開、公開後の分析までを、Drafityが月額で継続して行います。", response.body
    assert_no_match "つくり続けます", response.body
    assert_no_match "をテーマに", response.body
    assert_no_match "無料トライアル", response.body
  end

  test "root page stays the product landing page" do
    get root_path

    assert_response :success
    assert_match "無料トライアル", response.body
    assert_no_match "海外SEOを、", response.body
  end
end
