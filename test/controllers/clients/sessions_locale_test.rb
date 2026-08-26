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

  test "japanese login page does not overwrite account preferred_locale" do
    client = create_client!(preferred_locale: "en")

    get new_client_session_path
    assert_response :success

    post client_session_path, params: { client: { email: client.email, password: "password123" } }
    assert_redirected_to dashboard_root_path
    assert_equal "en", client.reload.preferred_locale

    follow_redirect!
    assert_response :success
    assert_includes response.body, "Create pillar article"
    refute_includes response.body, "親記事の作成開始"
  end

  test "english login page does not overwrite account preferred_locale" do
    client = create_client!(preferred_locale: "ja")

    post client_session_en_path(locale: :en), params: { client: { email: client.email, password: "password123" } }
    assert_redirected_to dashboard_root_path
    assert_equal "ja", client.reload.preferred_locale

    follow_redirect!
    assert_response :success
    assert_includes response.body, "親記事の作成開始"
    refute_includes response.body, "Create pillar article"
  end
end
