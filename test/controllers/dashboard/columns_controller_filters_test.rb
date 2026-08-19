require "test_helper"

class Dashboard::ColumnsControllerFiltersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "drafity.pro"
  end

  test "unauthenticated dashboard columns redirects to login not root" do
    get dashboard_columns_path

    assert_redirected_to new_client_session_path
    assert_equal I18n.t("drafity.auth.login_required"), flash[:alert]
    refute_equal root_path, new_client_session_path
  end
end
