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
    complete_client_first_run!(client)
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
    complete_client_first_run!(client)
    sign_in client

    get columns_index_path(genre: CrawlPolicy::GENRE_KEY)
    assert_response :success

    get dashboard_root_path
    assert_response :success
    assert_includes response.body, "Create pillar article"
    assert_not_includes response.body, "親記事の作成開始"
    assert_equal "en", client.reload.preferred_locale
  end

  test "japanese trial first-run wizard uses company and service without jargon fields" do
    client = create_trial_client!(preferred_locale: "ja")
    sign_in client

    get dashboard_start_path
    assert_response :success
    assert_includes response.body, "会社名"
    assert_includes response.body, "サービス名"
    assert_includes response.body, "3つのステップで最初の記事を作ります"
    assert_not_includes response.body, "name=\"service_genre[en]\""
    assert_not_includes response.body, "name=\"service_genre[column_cta][title]\""
    assert_not_includes response.body, "キー（英小文字"
    assert_not_includes response.body, "見出し（英語）"
    assert_not_includes response.body, "遷移先パス"
    assert_not_includes response.body, "CTAを表示する"
    assert_not_includes response.body, "Meetia"
    assert_not_includes response.body, "親記事の作成開始"
  end

  test "english trial first-run wizard uses company and service without jargon fields" do
    client = create_trial_client!(preferred_locale: "en")
    sign_in client

    get dashboard_start_path
    assert_response :success
    assert_includes response.body, "Company name"
    assert_includes response.body, "Service name"
    assert_includes response.body, "Create your first article in 3 steps"
    assert_not_includes response.body, "name=\"service_genre[ja]\""
    assert_not_includes response.body, "name=\"service_genre[column_cta][title]\""
    assert_not_includes response.body, "Headline (Japanese)"
    assert_not_includes response.body, "Headline (English)"
    assert_not_includes response.body, "Path (same domain)"
    assert_not_includes response.body, "Show CTA"
    assert_not_includes response.body, "Meetia"
    assert_not_includes response.body, "親記事の作成開始"
  end

  test "trial client saves company and service through the first-run wizard" do
    client = create_trial_client!(preferred_locale: "ja")
    sign_in client

    assert_difference("ServiceGenre.count", 1) do
      post dashboard_start_service_path, params: {
        onboarding: {
          company: "株式会社サンプル",
          service_name: "美容院",
          strong_points: "丁寧なカウンセリング"
        }
      }
    end

    genre = ServiceGenre.order(:id).last
    assert_equal "美容院", genre.ja
    assert_equal "美容院", genre.service_name
    assert_equal "株式会社サンプル", client.reload.company
    assert genre.key.present?
    assert_match(/\A[a-z0-9_]+\z/, genre.key)
    assert_not_equal "genre", genre.key
  end

  test "trial genre edit shows the saved name and article edit uses it" do
    client = create_trial_client!(preferred_locale: "ja")
    complete_client_first_run!(client)
    sign_in client

    post dashboard_service_genres_path, params: {
      service_genre: {
        ja: "美容院",
        company: "株式会社サンプル",
        column_cta: {
          enabled: "1",
          theme: "#2563eb",
          title: "無料カウンセリング"
        }
      }
    }
    genre = ServiceGenre.order(:id).last
    assert_equal "美容院", genre.ja

    get edit_dashboard_service_genre_path(genre)
    assert_response :success
    assert_select "input#service_genre_ja[value=?]", "美容院"

    patch dashboard_service_genre_path(genre), params: {
      service_genre: {
        ja: "ヘアサロン",
        company: "株式会社サンプル",
        column_cta: { enabled: "1", theme: "#2563eb", title: "無料カウンセリング" }
      }
    }
    assert_redirected_to dashboard_service_genres_path
    assert_equal "ヘアサロン", genre.reload.ja

    get dashboard_columns_path
    assert_response :success
    assert_select "select#genre-select-modal option[value=?]", genre.key, text: "ヘアサロン"

    column = client.columns.pillars.order(:id).first
    column.update_columns(genre: genre.key)
    get edit_column_path(column)
    assert_response :success
    assert_select "select#genre-select option[value=?]", genre.key, text: "ヘアサロン"
  end

  test "article edit shows saved japanese name even when genre key is genre" do
    client = create_trial_client!(preferred_locale: "ja")
    complete_client_first_run!(client)
    sign_in client
    leftover = client.service_genres.new(key: "genre", ja: "美容院", service_name: "美容院", sub_categories: {})
    leftover.admin_override = true
    leftover.save!

    column = client.columns.pillars.order(:id).first
    column.update_columns(genre: "genre", title: "旧キー記事")
    get edit_column_path(column)
    assert_response :success
    assert_select "select#genre-select option[value=?]", "genre", text: "美容院"
  end

  test "english trial saves notice copy to english fields only" do
    client = create_trial_client!(preferred_locale: "en")
    complete_client_first_run!(client)
    sign_in client

    assert_difference("ServiceGenre.count", 1) do
      post dashboard_service_genres_path, params: {
        service_genre: {
          en: "Hair salon",
          company: "Acme Inc.",
          column_cta: {
            enabled: "1",
            theme: "#2563eb",
            en: {
              title: "Book a consult",
              cta_label: "Learn more"
            }
          }
        }
      }
    end

    genre = ServiceGenre.order(:id).last
    assert_equal "Hair salon", genre.en
    assert_equal "Hair salon", genre.ja
    cta = genre.column_cta.with_indifferent_access
    assert_nil cta[:title]
    assert_equal "Book a consult", cta[:en][:title]
    assert_equal "Learn more", cta[:en][:cta_label]
  end

  def create_trial_client!(preferred_locale:)
    Client.create!(
      email: "genre-trial-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "Genre Trial Client",
      subscription_plan: "trial",
      subscription_status: "trialing",
      trial_ends_at: 14.days.from_now,
      preferred_locale: preferred_locale
    )
  end
end
