require "test_helper"

class Dashboard::LocaleIsolationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def create_client!(preferred_locale:)
    Client.create!(
      email: "locale-iso-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "Locale Isolation Client",
      subscription_plan: "business",
      subscription_status: "active",
      preferred_locale: preferred_locale
    )
  end

  setup do
    host! "drafity.pro"
  end

  test "english dashboard columns routes stay english after generation polling" do
    client = create_client!(preferred_locale: "en")
    sign_in client

    get dashboard_root_path
    assert_response :success
    assert_includes response.body, "Create pillar article"
    assert_not_includes response.body, "親記事の作成開始"

    get dashboard_columns_path(scope: "pending_review")
    assert_response :success
    assert_includes response.body, "Pending review"
    assert_includes response.body, "Create pillar article"
    assert_not_includes response.body, "親記事の作成開始"

    get generation_status_dashboard_columns_path
    assert_response :success

    get sidebar_badges_dashboard_columns_path
    assert_response :success

    get dashboard_root_path
    assert_response :success
    assert_includes response.body, "Create pillar article"
    assert_not_includes response.body, "親記事の作成開始"
    assert_equal "en", client.reload.preferred_locale
  end

  test "viewing japanese public articles does not switch english dashboard" do
    client = create_client!(preferred_locale: "en")
    sign_in client

    get columns_index_path(genre: CrawlPolicy::GENRE_KEY)
    assert_response :success

    get dashboard_root_path
    assert_response :success
    assert_includes response.body, "Create pillar article"
    assert_not_includes response.body, "親記事の作成開始"
    assert_equal "en", client.reload.preferred_locale
  end
end
