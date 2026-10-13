require "test_helper"

class OverseasSeoControllerTest < ActionDispatch::IntegrationTest
  test "consulting landing page is public" do
    get overseas_seo_path

    assert_response :success
    assert_match "98,000", response.body
    assert_match "市場調査", response.body
    assert_match "コンサルティング", response.body
    assert_no_match "無料トライアル", response.body
  end
end
