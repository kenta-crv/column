require "test_helper"

class ColumnTest < ActiveSupport::TestCase
  def create_trial_client
    Client.create!(
      email: "trial-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "Trial User"
    )
  end

  test "cannot change article type to pillar when pillar limit reached" do
    client = create_trial_client
    client.columns.create!(title: "Existing pillar", article_type: "pillar", genre: "other", status: "draft")

    cluster = client.columns.create!(title: "Cluster draft", article_type: "cluster", genre: "other", status: "draft")
    cluster.article_type = "pillar"

    assert_not cluster.valid?
    assert_includes cluster.errors.full_messages.join, "親記事の作成上限"
  end

  test "english_article? is false when language is missing or not selected" do
    column = Column.create!(title: "Language fallback", article_type: "pillar", genre: "other", status: "draft", language: "en")
    loaded = Column.select(:id, :code).find(column.id)

    refute loaded.has_attribute?(:language)
    refute loaded.english_article?
    refute Column.new.english_article?
    assert Column.new(language: "en").english_article?
  end

  test "blank or unusable code is not replaced with a UUID by FriendlyId" do
    blank = Column.create!(title: "Blank code", article_type: "pillar", genre: "other", status: "draft", code: "")
    japanese = Column.create!(title: "Japanese code", article_type: "pillar", genre: "other", status: "draft", code: "日本語スラッグ")

    assert_nil blank.code
    assert_equal "日本語スラッグ", japanese.code
    refute_match(Column::UUID_LIKE_CODE, blank.code.to_s)
    refute_match(Column::UUID_LIKE_CODE, japanese.code.to_s)
  end

  test "placeholder_code? treats UUID and blank values as assignable SEO codes" do
    uuid = "596b52d3-7d5f-46c8-8abb-92d3612d94ab"
    column = Column.new(code: uuid)

    assert Column.placeholder_code?(uuid)
    assert Column.placeholder_code?("")
    assert Column.placeholder_code?("日本語")
    assert Column.placeholder_code?("article-14")
    assert Column.placeholder_code?("btob")
    refute Column.placeholder_code?("anxious-candidate-ai-interview-care")
    refute Column.weak_seo_code?("ai-interview-care-2")
    assert Column.placeholder_code?("kpi-ai")
    assert_equal({ code: "seo-article-slug" }, column.seo_code_assignment("seo-article-slug"))
  end

  test "fallback_seo_code builds a multi-word slug from a Japanese title" do
    column = Column.new(title: "売上が変わる決定的要因｜自動販売機設置で失敗しないロケーション選定の極意", genre: "vender")
    slug = Column.fallback_seo_code(column)

    assert_includes slug, "vending-machine"
    assert_includes slug, "installation"
    refute Column.weak_seo_code?(slug)
  end

  test "persist_seo_code! keeps the old UUID findable and uses a unique slug" do
    uuid = "596b52d3-7d5f-46c8-8abb-92d3612d94ab"
    taken = Column.create!(title: "Taken slug", article_type: "pillar", genre: "other", status: "draft", code: "ai-interview-care")
    column = Column.create!(title: "Needs slug", article_type: "pillar", genre: "other", status: "draft", code: uuid)

    column.persist_seo_code!("ai-interview-care")

    assert_equal "ai-interview-care-2", column.reload.code
    assert_equal column.id, Column.find_by_param(uuid).id
    assert_equal column.id, Column.find_by_param(column.code).id
    assert_equal taken.id, Column.find_by_param("ai-interview-care").id
  end

  test "generated_body? uses body_present from list attributes without loading body" do
    client = create_trial_client
    with_body = client.columns.create!(title: "With body", article_type: "cluster", genre: "other", status: "draft", body: "# Hello")
    without_body = client.columns.create!(title: "Without body", article_type: "cluster", genre: "other", status: "draft", body: nil)

    listed = Column.where(id: [with_body.id, without_body.id]).with_list_attributes.index_by(&:id)

    assert_equal true, listed[with_body.id].generated_body?
    assert_equal false, listed[without_body.id].generated_body?
    assert_equal false, listed[with_body.id].has_attribute?(:body)
  end

  test "generation failure dump is not treated as a generated article" do
    client = create_trial_client
    failed = client.columns.create!(
      title: "Failed dump",
      article_type: "cluster",
      genre: "other",
      status: "error",
      body: "❌ 失敗: RuntimeError - 本文の生成に失敗しました（内容が空、またはエラーメッセージが含まれています）\n場所: app/jobs/generate_column_body_job.rb:54"
    )
    ok = client.columns.create!(
      title: "Real article",
      article_type: "cluster",
      genre: "other",
      status: "completed",
      body: "# 現場の責任分界\n\n契約条件を具体化する。"
    )

    refute failed.generated_body?
    assert ok.generated_body?
    assert_includes Column.without_generated_body.pluck(:id), failed.id
    assert_includes Column.drafts.pluck(:id), failed.id
    refute_includes Column.with_generated_body.pluck(:id), failed.id
    assert_includes Column.with_generated_body.pluck(:id), ok.id
    refute_includes Column.publicly_listed.pluck(:id), failed.id

    listed = Column.where(id: [failed.id, ok.id]).with_list_attributes.index_by(&:id)
    assert_equal false, listed[failed.id].generated_body?
    assert_equal true, listed[ok.id].generated_body?
  end

  test "unpublished runtime error body is a draft not pending review" do
    client = create_trial_client
    failed = client.columns.create!(
      title: "Runtime dump",
      article_type: "child",
      genre: "other",
      status: "error",
      published_at: nil,
      body: "❌ 失敗: RuntimeError - 本文の生成に失敗しました\n場所: app/jobs/generate_column_body_job.rb:54"
    )
    review = client.columns.create!(
      title: "Ready",
      article_type: "child",
      genre: "other",
      status: "completed",
      published_at: nil,
      body: "# 本文\n\n契約条件を具体化する。"
    )
    published_ok = client.columns.create!(
      title: "Live",
      article_type: "child",
      genre: "other",
      status: "completed",
      published_at: Time.current,
      body: "# 本文\n\n公開できる記事。"
    )
    published_error = client.columns.create!(
      title: "Live error",
      article_type: "child",
      genre: "other",
      status: "error",
      published_at: Time.current,
      body: "❌ 失敗: RuntimeError - 本文の生成に失敗しました"
    )

    assert_includes Column.drafts.pluck(:id), failed.id
    refute_includes Column.pending_review.pluck(:id), failed.id
    assert_includes Column.pending_review.pluck(:id), review.id
    assert_includes Column.publicly_listed.pluck(:id), published_ok.id
    refute_includes Column.publicly_listed.pluck(:id), published_error.id
    assert_includes Column.drafts.pluck(:id), published_error.id
  end

  test "cleared body is a draft even if published_at remains" do
    client = create_trial_client
    column = client.columns.create!(
      title: "Cleared",
      article_type: "child",
      genre: "other",
      status: "error",
      published_at: Time.current,
      body: nil
    )
    spaced = client.columns.create!(
      title: "Whitespace only",
      article_type: "child",
      genre: "other",
      status: "draft",
      published_at: nil,
      body: "   "
    )

    assert_includes Column.drafts.pluck(:id), column.id
    assert_includes Column.drafts.pluck(:id), spaced.id
    refute column.generated_body?
    refute_includes Column.publicly_listed.pluck(:id), column.id
    refute_includes Column.pending_review.pluck(:id), column.id
  end
end
