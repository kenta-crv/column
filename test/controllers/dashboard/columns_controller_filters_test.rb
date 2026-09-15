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

  test "draft tab counts unpublished runtime error bodies as drafts" do
    admin = Admin.create!(email: "admin-tabs-#{SecureRandom.hex(4)}@example.com", password: "password123")
    sign_in admin

    empty_draft = Column.create!(
      title: "Empty draft",
      article_type: "child",
      genre: "other",
      status: "draft",
      body: nil,
      code: "tab-empty-#{SecureRandom.hex(3)}"
    )
    runtime_dump = Column.create!(
      title: "Runtime dump",
      article_type: "child",
      genre: "other",
      status: "error",
      published_at: nil,
      body: "❌ 失敗: RuntimeError - 本文の生成に失敗しました\n場所: generate_column_body_job.rb:54",
      code: "tab-dump-#{SecureRandom.hex(3)}"
    )
    published_ok = Column.create!(
      title: "Published ok",
      article_type: "child",
      genre: "other",
      status: "completed",
      published_at: Time.current,
      body: "# 公開本文\n\n現場の条件を整理する。",
      code: "tab-pub-#{SecureRandom.hex(3)}"
    )
    body_deleted = Column.create!(
      title: "Body deleted but still published",
      article_type: "child",
      genre: "other",
      status: "error",
      published_at: Time.current,
      body: nil,
      code: "tab-cleared-#{SecureRandom.hex(3)}"
    )

    get dashboard_columns_path
    assert_response :success

    counts = Dashboard::ColumnsController.new.send(
      :compute_dashboard_tab_counts,
      Column.where(id: [empty_draft.id, runtime_dump.id, published_ok.id, body_deleted.id])
    )
    draft_count = counts[1]
    published_count = counts[5]
    error_count = counts[6]

    assert_equal 3, draft_count
    assert_equal 1, published_count
    assert_operator error_count, :>=, 1

    get dashboard_columns_path(scope: "draft")
    assert_response :success
    assert_match "Runtime dump", response.body
    assert_match "Empty draft", response.body
    assert_match "Body deleted but still published", response.body
    refute_match "Published ok", response.body
  end

  test "english dashboard lists every article language" do
    admin = Admin.create!(email: "admin-lang-#{SecureRandom.hex(4)}@example.com", password: "password123")
    sign_in admin

    ja = Column.create!(
      title: "日本語ダッシュボード記事",
      article_type: "pillar",
      genre: CrawlPolicy::GENRE_KEY,
      status: "draft",
      language: "ja",
      code: "dash-ja-#{SecureRandom.hex(3)}"
    )
    en = Column.create!(
      title: "English dashboard article XYZ",
      article_type: "pillar",
      genre: CrawlPolicy::GENRE_KEY,
      status: "draft",
      language: "en",
      code: "dash-en-#{SecureRandom.hex(3)}"
    )
    hiragana = Column.create!(
      title: "ひらがなダッシュボード記事",
      article_type: "pillar",
      genre: CrawlPolicy::GENRE_KEY,
      status: "draft",
      language: "hiragana",
      code: "dash-hrkt-#{SecureRandom.hex(3)}"
    )

    get switch_locale_path(locale: "en", return_to: dashboard_columns_path)

    get dashboard_columns_path
    assert_response :success
    assert_includes response.body, "Create pillar article"
    assert_includes response.body, ja.title
    assert_includes response.body, en.title
    assert_includes response.body, hiragana.title
    assert_select "#language-select", count: 0

    get dashboard_columns_path(language: "en")
    assert_response :success
    assert_includes response.body, ja.title
    assert_includes response.body, en.title
    assert_includes response.body, hiragana.title
  end

  test "genre summary shows the service name instead of the generated key" do
    client = Client.create!(
      email: "genre-summary-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "Genre Summary Client",
      subscription_plan: "trial",
      subscription_status: "trialing",
      trial_ends_at: 14.days.from_now,
      preferred_locale: "ja"
    )
    sign_in client
    post dashboard_start_service_path, params: {
      onboarding: {
        company: "株式会社サンプル",
        service_name: "オンライン英会話"
      }
    }
    genre = client.reload.service_genres.order(:id).last
    assert_match(/\Asvc/, genre.key)
    complete_client_first_run!(client)

    get dashboard_columns_path
    assert_response :success
    assert_select ".genre-summary-name", text: "オンライン英会話"
    assert_select ".genre-summary-name", text: genre.key, count: 0
  end
end
