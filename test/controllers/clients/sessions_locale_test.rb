require "test_helper"

class Clients::SessionsLocaleTest < ActionDispatch::IntegrationTest
  def create_client!(preferred_locale:)
    Client.create!(
      email: "locale-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "Locale Client",
      subscription_plan: "business",
      subscription_status: "active",
      preferred_locale: preferred_locale
    )
  end

  test "japanese login page keeps dashboard in japanese even if account preferred_locale is en" do
    client = create_client!(preferred_locale: "en")

    get new_client_session_path
    assert_response :success

    post client_session_path, params: { client: { email: client.email, password: "password123" } }
    assert_redirected_to dashboard_root_path
    assert_equal "ja", client.reload.preferred_locale

    follow_redirect!
    assert_response :success
    assert_includes response.body, "ダッシュボード"
    refute_includes response.body, ">Dashboard<"
  end

  test "english login page keeps dashboard in english even if account preferred_locale is ja" do
    client = create_client!(preferred_locale: "ja")

    post client_session_en_path(locale: :en), params: { client: { email: client.email, password: "password123" } }
    assert_redirected_to dashboard_root_path
    assert_equal "en", client.reload.preferred_locale

    follow_redirect!
    assert_response :success
    assert_includes response.body, "Dashboard"
  end
end
