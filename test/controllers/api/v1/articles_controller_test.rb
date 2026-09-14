require "test_helper"

class Api::V1::ArticlesControllerTest < ActionDispatch::IntegrationTest
  def setup_fixtures; end
  def teardown_fixtures; end

  def create_api_client!
    client = Client.create!(
      email: "api-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "API Client"
    )
    client.subscriptions.where(status: :active).update_all(status: :cancelled)
    client.subscriptions.create!(plan_type: :business, status: :active)
    client.update!(subscription_plan: "business", subscription_status: "active")
    client.service_genres.create!(
      key: "api_genre_#{SecureRandom.hex(3)}",
      ja: "API確認",
      sub_categories: {},
      admin_override: true
    )
    client
  end

  def create_published!(client, attrs)
    genre_key = client.service_genres.first.key
    client.columns.create!(
      {
        title: "公開記事",
        body: "# 本文\n\n公開用です。",
        genre: genre_key,
        code: "api-#{SecureRandom.hex(4)}",
        article_type: "pillar",
        published_at: Time.current,
        status: "completed",
        language: "ja"
      }.merge(attrs)
    )
  end

  test "embed html lists only japanese articles by default" do
    client = create_api_client!
    ja = create_published!(client, title: "日本語埋め込み記事", language: "ja")
    en = create_published!(client, title: "English embed article", language: "en")

    post "/api/v1/articles/render_html", params: { api_key: client.api_key }

    assert_response :success
    assert_includes response.body, ja.title
    refute_includes response.body, en.title
  end

  test "embed html lists only english articles when language is en" do
    client = create_api_client!
    ja = create_published!(client, title: "日本語埋め込み記事", language: "ja")
    en = create_published!(client, title: "English embed article", language: "en")

    post "/api/v1/articles/render_html", params: { api_key: client.api_key, language: "en" }

    assert_response :success
    assert_includes response.body, en.title
    refute_includes response.body, ja.title
  end
end
