require "test_helper"

class ColumnsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup_fixtures; end
  def teardown_fixtures; end

  def create_admin!
    Admin.create!(
      email: "admin-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
  end

  def create_client!(suffix:, preferred_locale: "ja")
    Client.create!(
      email: "client-#{suffix}-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "Client #{suffix}",
      subscription_plan: "business",
      subscription_status: "active",
      preferred_locale: preferred_locale
    )
  end

  test "admin pillar manage index lists pillars across genres on platform host" do
    admin = create_admin!
    drafity_client = create_client!(suffix: "drafity")
    other_client = create_client!(suffix: "other")

    drafity_pillar = drafity_client.columns.create!(
      title: "Drafity Pillar",
      article_type: "pillar",
      genre: CrawlPolicy::GENRE_KEY,
      status: "draft",
      code: "drafity-pillar-#{SecureRandom.hex(3)}"
    )
    other_pillar = other_client.columns.create!(
      title: "Other Client Pillar",
      article_type: "pillar",
      genre: "security",
      status: "draft",
      code: "other-pillar-#{SecureRandom.hex(3)}"
    )

    host! "drafity.pro"
    sign_in admin

    get columns_path(article_type: "pillar")
    assert_response :success
    assert_includes response.body, drafity_pillar.title
    assert_includes response.body, other_pillar.title
  end

  test "signed-in public English index filters by language and is not manage view" do
    admin = create_admin!
    ja_client = create_client!(suffix: "public-ja")
    en_client = create_client!(suffix: "public-en")

    ja_column = ja_client.columns.create!(
      title: "日本語公開記事タイトルXYZ",
      article_type: "pillar",
      genre: CrawlPolicy::GENRE_KEY,
      status: "draft",
      code: "ja-public-#{SecureRandom.hex(3)}",
      body: "# 日本語本文\n\n公開用の本文です。",
      published_at: Time.current,
      language: "ja"
    )
    en_column = en_client.columns.create!(
      title: "English published article title XYZ",
      article_type: "pillar",
      genre: CrawlPolicy::GENRE_KEY,
      status: "draft",
      code: "en-public-#{SecureRandom.hex(3)}",
      body: "# English body\n\nPublished English article.",
      published_at: Time.current,
      language: "en"
    )

    host! "drafity.pro"
    sign_in admin

    get localized_columns_index_path(locale: :en, genre: CrawlPolicy::GENRE_KEY)
    assert_response :success
    assert_includes response.body, en_column.title
    assert_not_includes response.body, ja_column.title
    assert_not_includes response.body, "Dashboardに戻る"
    assert_includes response.body, "Published articles"

    get columns_path
    assert_response :success
    assert_includes response.body, ja_column.title
    assert_includes response.body, en_column.title
  end

  test "english client sees publish status panel in english" do
    client = create_client!(suffix: "en-ui", preferred_locale: "en")
    column = client.columns.create!(
      title: "English pending article",
      article_type: "pillar",
      genre: CrawlPolicy::GENRE_KEY,
      status: "draft",
      code: "en-pending-#{SecureRandom.hex(3)}",
      body: "# English body\n\nAwaiting review.",
      language: "en"
    )

    host! "drafity.pro"
    sign_in client

    get column_path(column)
    assert_response :success
    assert_includes response.body, "This article is awaiting review"
    assert_includes response.body, "Review complete"
    assert_not_includes response.body, "この記事はレビュー待ちです"

    patch publish_column_path(column)
    assert_response :redirect
    assert_equal I18n.t("drafity.columns.manage.published_notice", locale: :en), flash[:notice]
    assert column.reload.published?

    get column_path(column)
    assert_response :success
    assert_includes response.body, "This article is published"
    assert_includes response.body, "Unpublish (back to draft)"
    assert_not_includes response.body, "この記事は公開済みです"
  end

  test "english article shows Contents instead of 目次" do
    admin = create_admin!
    column = Column.create!(
      title: "English TOC article",
      article_type: "pillar",
      genre: CrawlPolicy::GENRE_KEY,
      status: "completed",
      code: "en-toc-#{SecureRandom.hex(3)}",
      language: "en",
      body: "Intro paragraph.\n\n## 目次\n\n- First section\n\n## First section\n\nBody."
    )

    host! "drafity.pro"
    sign_in admin

    get column_path(column)
    assert_response :success
    assert_includes response.body, "toc-title"
    assert_includes response.body, "Contents"
    assert_not_includes response.body, ">目次<"
  end

  test "admin can add child titles when pillar cluster_limit is 1" do
    admin = create_admin!
    pillar = Column.create!(
      title: "Admin cluster limit one",
      article_type: "pillar",
      genre: CrawlPolicy::GENRE_KEY,
      status: "draft",
      cluster_limit: 1,
      code: "admin-limit1-#{SecureRandom.hex(3)}"
    )
    Column.create!(
      title: "Existing child",
      article_type: "child",
      parent_id: pillar.id,
      genre: pillar.genre,
      status: "draft",
      code: "admin-child-#{SecureRandom.hex(3)}"
    )

    host! "drafity.pro"
    sign_in admin

    get column_path(pillar)
    assert_response :success
    assert_includes response.body, I18n.t("drafity.columns.manage.generate_titles")
    assert_not_includes response.body, I18n.t("drafity.columns.manage.title_limit")
  end

  test "public show 301s historic UUID code to current SEO code" do
    old_code = "596b52d3-7d5f-46c8-8abb-92d3612d94ab"
    column = Column.create!(
      title: "Published UUID article",
      article_type: "pillar",
      genre: CrawlPolicy::GENRE_KEY,
      status: "completed",
      code: "canonical-ai-interview-#{SecureRandom.hex(3)}",
      body: "# Hello\n\nPublished body for canonical redirect.",
      published_at: Time.current,
      language: "ja"
    )
    FriendlyId::Slug.create!(slug: old_code, sluggable_id: column.id, sluggable_type: "Column")

    host! "drafity.pro"
    get columns_show_path(genre: CrawlPolicy::GENRE_KEY, id: old_code)
    assert_response :moved_permanently
    assert_redirected_to columns_show_path(genre: CrawlPolicy::GENRE_KEY, id: column.code)
  end

  test "brand host public show 301s historic UUID to /columns/slug" do
    old_code = "3b6f5603-315f-49ef-a1f3-d50385a65a76"
    column = Column.create!(
      title: "Recrivo UUID article",
      article_type: "pillar",
      genre: "ai_interview",
      status: "completed",
      code: "franchise-ai-interview-#{SecureRandom.hex(3)}",
      body: "# Hello\n\nPublished body for brand canonical redirect.",
      published_at: Time.current,
      language: "ja"
    )
    FriendlyId::Slug.create!(slug: old_code, sluggable_id: column.id, sluggable_type: "Column")

    host! "recrivo.pro"
    get "/columns/#{old_code}"
    assert_response :moved_permanently
    assert_equal "/columns/#{column.code}", response.redirect_url.sub(%r{\Ahttps?://[^/]+}, "")
  end
end
