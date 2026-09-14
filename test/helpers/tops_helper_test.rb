require "test_helper"

class TopsHelperTest < ActionView::TestCase
  include TopsHelper

  def setup_fixtures; end
  def teardown_fixtures; end

  def create_published!(attrs)
    Column.create!(
      {
        title: "公開記事",
        body: "# 本文\n\n公開用です。",
        genre: CrawlPolicy::GENRE_KEY,
        code: "top-#{SecureRandom.hex(4)}",
        article_type: "pillar",
        published_at: Time.current,
        status: "completed",
        language: "ja"
      }.merge(attrs)
    )
  end

  test "japanese homepage featured articles exclude english columns" do
    ja = create_published!(
      title: "日本語の注目記事-#{SecureRandom.hex(3)}",
      code: "top-ja-#{SecureRandom.hex(3)}",
      language: "ja",
      updated_at: Time.current
    )
    en = create_published!(
      title: "English featured #{SecureRandom.hex(3)}",
      code: "top-en-#{SecureRandom.hex(3)}",
      language: "en",
      updated_at: Time.current
    )

    I18n.with_locale(:ja) do
      titles = featured_ai_article_columns(limit: 5).map { |item| item[:title] }
      refute_includes titles, en.title
    end

    I18n.with_locale(:en) do
      titles = featured_ai_article_columns(limit: 5).map { |item| item[:title] }
      refute_includes titles, ja.title
    end
  end

  test "english homepage does not fall back to japanese articles" do
    ja = create_published!(
      title: "日本語だけの公開記事-#{SecureRandom.hex(3)}",
      code: "top-ja-only-#{SecureRandom.hex(3)}",
      language: "ja"
    )
    Column.where(language: "en").update_all(published_at: nil)

    I18n.with_locale(:en) do
      items = featured_ai_article_columns(limit: 5)
      titles = items.map { |item| item[:title] }

      assert_empty items
      refute_includes titles, ja.title
      refute_includes titles, "GEO-powered content strategy that works"
    end
  end
end
