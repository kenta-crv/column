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

    get columns_index_path(genre: CrawlPolicy::GENRE_KEY)
    assert_response :success
    assert_includes response.body, ja_column.title
    assert_not_includes response.body, en_column.title
  end

  test "english published article on japanese public path redirects to /en" do
    column = Column.create!(
      title: "Event tracking churn points for B2B sales",
      article_type: "pillar",
      genre: CrawlPolicy::GENRE_KEY,
      status: "completed",
      code: "event-tracking-churn-points-b2b-sales-#{SecureRandom.hex(3)}",
      body: "# English body\n\nPublished English article.",
      published_at: Time.current,
      language: "en"
    )

    host! "drafity.pro"
    get columns_show_path(genre: CrawlPolicy::GENRE_KEY, id: column.code)
    assert_response :moved_permanently
    assert_redirected_to localized_columns_show_path(
      locale: :en,
      genre: CrawlPolicy::GENRE_KEY,
      id: column.code
    )
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

  test "brand host public show 301s a slug with a trailing UUID to the slug without it" do
    suffix = "fb994e66-4617-4210-8561-ec6f07ba0dfa"
    column = Column.create!(
      title: "BtoB PDCA",
      article_type: "pillar",
      genre: "ai_interview",
      status: "completed",
      code: "btob-eigyou-kaizen-pdca-#{suffix}",
      body: "# Hello\n\nPublished body for trailing UUID redirect.",
      published_at: Time.current,
      language: "ja"
    )

    host! "recrivo.pro"
    get "/columns/#{column.code}"

    assert_response :moved_permanently
    assert_equal "/columns/btob-eigyou-kaizen-pdca", response.redirect_url.sub(%r{\Ahttps?://[^/]+}, "")
    assert_equal "btob-eigyou-kaizen-pdca", column.reload.code
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

  test "brand host does not redirect when nginx already shows the public slug" do
    column = Column.create!(
      title: "Canonical interview article",
      article_type: "pillar",
      genre: "ai_interview",
      status: "completed",
      code: "already-canonical-interview-slug",
      body: "# Hello\n\nPublished body.",
      published_at: Time.current,
      language: "ja"
    )

    host! "recrivo.pro"
    get "/ai_interview/columns/#{column.code}"
    assert_response :ok

    get "/columns/#{column.code}"
    assert_response :ok
  end

  test "brand host sends the numbered operations slug to the descriptive path once" do
    column = Column.create!(
      title: "AI面接導入のロードマップ",
      article_type: "cluster",
      genre: "ai_interview",
      status: "completed",
      code: "ai-interview-operations-2",
      body: "# Hello\n\nPublished roadmap.",
      published_at: Time.current,
      language: "ja"
    )

    host! "recrivo.pro"
    get "/ai_interview/columns/ai-interview-operations-2"
    assert_response :moved_permanently
    assert_equal "/columns/ai-interview-rollout-schedule", response.redirect_url.sub(%r{\Ahttps?://[^/]+}, "")

    get "/ai_interview/columns/ai-interview-rollout-schedule"
    assert_response :ok
  end

  test "public article pages use the analytics id of the requesting site" do
    host! "drafity.pro"
    get root_path
    assert_response :success
    assert_includes response.body, "gtag/js?id=G-T2EEN55SZ1"
    assert_includes response.body, "gtag('config', 'G-T2EEN55SZ1')"

    {
      "j-work.jp" => "G-1PSQHCJF86",
      "kurasera.life" => "G-CCZ47DWBCY",
      "meetia.pro" => "G-YCZ141VD12",
      "okey.work" => "G-SZLWY1TPZF",
      "okurite.pro" => "G-E4V9G3H3D5",
      "recrivo.pro" => "G-YZVT6M6CNF",
      "www.recrivo.pro" => "G-YZVT6M6CNF",
      "xn--new351c2sh.net" => "G-8TH2BJHDNP",
      "自販機.net" => "G-8TH2BJHDNP"
    }.each do |forwarded_host, measurement_id|
      get root_path, headers: { "X-Forwarded-Host" => forwarded_host }
      assert_response :success
      assert_includes response.body, "gtag/js?id=#{measurement_id}"
      assert_includes response.body, "gtag('config', '#{measurement_id}')"
      assert_not_includes response.body, "G-T2EEN55SZ1"
    end

    column = Column.create!(
      title: "Okurite analytics article",
      article_type: "pillar",
      genre: "app",
      status: "completed",
      code: "okurite-analytics-#{SecureRandom.hex(3)}",
      body: "# Hello\n\nPublished body for analytics.",
      published_at: Time.current,
      language: "ja"
    )
    get "/app/columns/#{column.code}", headers: { "X-Forwarded-Host" => "okurite.pro" }
    assert_response :success
    assert_includes response.body, "gtag('config', 'G-E4V9G3H3D5')"
    assert_not_includes response.body, "G-T2EEN55SZ1"

    recrivo_column = Column.create!(
      title: "Recrivo analytics article",
      article_type: "pillar",
      genre: "ai_interview",
      status: "completed",
      code: "recrivo-analytics-#{SecureRandom.hex(3)}",
      body: "# Hello\n\nPublished body for analytics.",
      published_at: Time.current,
      language: "ja"
    )
    get "/ai_interview/columns/#{recrivo_column.code}", headers: { "X-Forwarded-Host" => "recrivo.pro" }
    assert_response :success
    assert_includes response.body, "gtag('config', 'G-YZVT6M6CNF')"
    assert_not_includes response.body, "G-T2EEN55SZ1"
  end

  test "signed-in admin screens do not load analytics" do
    admin = create_admin!
    host! "drafity.pro"
    sign_in admin

    get contracts_path
    assert_response :success
    assert_not_includes response.body, "googletagmanager.com/gtag/js"
    assert_not_includes response.body, "G-T2EEN55SZ1"

    get new_contract_path
    assert_response :success
    assert_includes response.body, "gtag('config', 'G-T2EEN55SZ1')"
  end
end
