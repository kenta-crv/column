require "test_helper"

class CrawlableSitemapTest < ActiveSupport::TestCase
  def setup_fixtures; end
  def teardown_fixtures; end

  setup do
    @original_xml = CrawlableSitemap::SITEMAP_PATH.exist? ? CrawlableSitemap::SITEMAP_PATH.read : nil
  end

  teardown do
    if @original_xml
      CrawlableSitemap::SITEMAP_PATH.write(@original_xml)
    elsif CrawlableSitemap::SITEMAP_PATH.exist?
      CrawlableSitemap::SITEMAP_PATH.delete
    end
  end

  def create_published!(attrs)
    Column.create!(
      {
        title: "公開記事",
        body: "# 本文\n\n公開用です。",
        genre: CrawlPolicy::GENRE_KEY,
        code: "sm-#{SecureRandom.hex(4)}",
        article_type: "pillar",
        published_at: Time.current,
        status: "completed"
      }.merge(attrs)
    )
  end

  test "crawlable_columns includes Japanese genre label used on the public index" do
    ja_label = GenreRegistry.to_ja(CrawlPolicy::GENRE_KEY)
    skip "ja label missing" if ja_label.blank?

    included = create_published!(title: "JA genre", code: "sm-ja-#{SecureRandom.hex(3)}")
    included.update_column(:genre, ja_label)

    excluded = create_published!(
      title: "Other genre",
      genre: "cargo",
      code: "sm-cargo-#{SecureRandom.hex(3)}"
    )
    unpublished = create_published!(
      title: "Unpublished",
      published_at: nil,
      code: "sm-unpub-#{SecureRandom.hex(3)}"
    )
    no_code = create_published!(title: "No code", code: "sm-nocode-#{SecureRandom.hex(3)}")
    no_code.update_column(:code, "")

    generation = create_published!(
      title: "Generation genre",
      genre: "ai_article_generation",
      code: "sm-gen-#{SecureRandom.hex(3)}"
    )
    generation_ja = GenreRegistry.to_ja("ai_article_generation")
    generation_ja_column = create_published!(
      title: "Generation JA genre",
      code: "sm-genja-#{SecureRandom.hex(3)}"
    )
    generation_ja_column.update_column(:genre, generation_ja.presence || "AI記事生成")

    ids = CrawlPolicy.crawlable_columns.pluck(:id)
    assert_includes ids, included.id
    refute_includes ids, excluded.id
    refute_includes ids, unpublished.id
    refute_includes ids, no_code.id
    refute_includes ids, generation.id
    refute_includes ids, generation_ja_column.id
    assert CrawlPolicy.crawlable_genre_values.all? { |value| CrawlPolicy.crawlable_genre?(value) }
  end

  test "column_path prefixes English articles and stays Japanese without language" do
    ja = create_published!(code: "sm-ja-path-#{SecureRandom.hex(3)}", language: "ja")
    en = create_published!(code: "sm-en-path-#{SecureRandom.hex(3)}", language: "en")
    without_language = Column.select(:id, :code).find(ja.id)

    assert_equal "/#{CrawlPolicy::GENRE_KEY}/columns/#{ja.code}", CrawlPolicy.column_path(ja)
    assert_equal "/en/#{CrawlPolicy::GENRE_KEY}/columns/#{en.code}", CrawlPolicy.column_path(en)
    assert_equal "/#{CrawlPolicy::GENRE_KEY}/columns/#{ja.code}", CrawlPolicy.column_path(without_language)
  end

  test "refresh! writes listing and published article locs" do
    column = create_published!(
      title: "Sitemap article",
      code: "sm-article-#{SecureRandom.hex(3)}"
    )

    CrawlableSitemap.refresh!
    xml = CrawlableSitemap::SITEMAP_PATH.read

    assert_includes xml, "https://drafity.pro/#{CrawlPolicy::GENRE_KEY}/columns</loc>"
    assert_includes xml, "https://drafity.pro#{CrawlPolicy.column_path(column)}</loc>"
    refute_includes xml, "This XML file does not appear to have any style information"

    loc_count = xml.scan("<loc>").size
    assert_equal CrawlPolicy::STATIC_PATHS.size + CrawlPolicy.crawlable_columns.count, loc_count
  end
end
