require "test_helper"

class Clients::RegistrationsLocaleTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "drafity.pro"
  end

  test "japanese signup keeps dashboard in japanese even if ui_locale cookie is en" do
    get localized_root_path(locale: :en)
    cookies[:ui_locale] = "en"

    get new_client_registration_path
    assert_response :success
    assert_includes response.body, "新規登録"

    email = "signup-ja-#{SecureRandom.hex(4)}@example.com"
    post "/clients", params: {
      client: {
        email: email,
        password: "password123",
        password_confirmation: "password123",
        preferred_locale: "ja"
      }
    }
    assert_redirected_to dashboard_root_path

    client = Client.find_by!(email: email)
    assert_equal "ja", client.preferred_locale

    follow_redirect!
    assert_response :success
    assert_includes response.body, "親記事の作成開始"
    assert_not_includes response.body, "Create pillar article"
  end

  test "japanese signup post stays japanese when cookie is en even without preferred_locale param" do
    cookies[:ui_locale] = "en"

    email = "signup-ja-cookie-#{SecureRandom.hex(4)}@example.com"
    post "/clients", params: {
      client: {
        email: email,
        password: "password123",
        password_confirmation: "password123"
      }
    }
    assert_redirected_to dashboard_root_path
    assert_equal "ja", Client.find_by!(email: email).preferred_locale

    follow_redirect!
    assert_response :success
    assert_includes response.body, "親記事の作成開始"
    assert_not_includes response.body, "Create pillar article"
  end

  test "english signup keeps dashboard in english even if ui_locale cookie is ja" do
    cookies[:ui_locale] = "ja"

    email = "signup-en-#{SecureRandom.hex(4)}@example.com"
    post client_registration_en_path(locale: :en), params: {
      client: {
        email: email,
        password: "password123",
        password_confirmation: "password123",
        preferred_locale: "en"
      }
    }
    assert_redirected_to dashboard_root_path

    client = Client.find_by!(email: email)
    assert_equal "en", client.preferred_locale

    follow_redirect!
    assert_response :success
    assert_includes response.body, "Create pillar article"
    assert_not_includes response.body, "親記事の作成開始"
  end

  test "japanese signup ignores leftover english session locale" do
    cookies[:ui_locale] = "en"

    get new_client_registration_path
    assert_response :success
    assert_includes response.body, "新規登録"
    assert_select "input[name='client[preferred_locale]'][value='ja']"

    email = "signup-ignore-session-#{SecureRandom.hex(4)}@example.com"
    post "/clients", params: {
      client: {
        email: email,
        password: "password123",
        password_confirmation: "password123",
        preferred_locale: "en"
      }
    }
    assert_redirected_to dashboard_root_path
    assert_equal "ja", Client.find_by!(email: email).preferred_locale

    follow_redirect!
    assert_response :success
    assert_includes response.body, "親記事の作成開始"
    assert_not_includes response.body, "Create pillar article"
  end

  test "client signup is rejected while admin is signed in" do
    admin = Admin.create!(
      email: "admin-leftover-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    sign_in admin

    email = "signup-after-admin-#{SecureRandom.hex(4)}@example.com"
    post "/clients", params: {
      client: {
        email: email,
        password: "password123",
        password_confirmation: "password123",
        preferred_locale: "ja"
      }
    }
    assert_redirected_to dashboard_root_path
    assert_equal I18n.t("drafity.auth.admin_session_blocks_client"), flash[:alert]
    assert_nil Client.find_by(email: email)

    follow_redirect!
    assert_response :success
    assert_includes response.body, "ログアウト (管理者)"
  end

  test "new signup fires yahoo ads conversion once on dashboard" do
    email = "trial-cv-#{SecureRandom.hex(4)}@example.com"
    post "/clients", params: {
      client: {
        email: email,
        password: "password123",
        password_confirmation: "password123"
      }
    }
    assert_redirected_to dashboard_root_path

    follow_redirect!
    assert_response :success
    assert_includes response.body, "PI10CNNARJJWSR9XZS1366128"
    assert_includes response.body, "yjad_conversion"

    get dashboard_root_path
    assert_response :success
    assert_not_includes response.body, "PI10CNNARJJWSR9XZS1366128"
  end
end
