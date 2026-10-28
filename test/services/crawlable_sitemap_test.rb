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

  test "crawlable_columns matches dashboard ai_article key and excludes other genres" do
    ja_label = GenreRegistry.to_ja(CrawlPolicy::GENRE_KEY)
    skip "ja label missing" if ja_label.blank?

    token = SecureRandom.hex(8)
    included = create_published!(title: "Key genre", code: "sm-key-#{token}")
    ja_labeled = create_published!(title: "JA genre", code: "sm-jalbl-#{token}")
    ja_labeled.update_column(:genre, ja_label)

    excluded = create_published!(
      title: "Other genre",
      genre: "cargo",
      code: "sm-cargo-#{token}"
    )
    unpublished = create_published!(
      title: "Unpublished",
      published_at: nil,
      code: "sm-unpub-#{token}"
    )
    no_code = create_published!(title: "No code", code: "sm-nocode-#{token}")
    no_code.update_column(:code, nil)

    generation = create_published!(
      title: "Generation genre",
      genre: "ai_article_generation",
      code: "sm-gen-#{token}"
    )
    generation_ja = GenreRegistry.to_ja("ai_article_generation")
    generation_ja_column = create_published!(
      title: "Generation JA genre",
      code: "sm-genja-#{token}"
    )
    generation_ja_column.update_column(:genre, generation_ja.presence || "自社記事")

    overseas = create_published!(
      title: "Overseas SEO",
      genre: CrawlPolicy::OVERSEAS_SEO_GENRE_KEY,
      code: "sm-overseas-#{token}"
    )

    ids = CrawlPolicy.crawlable_columns.pluck(:id)
    assert_includes ids, included.id
    assert_includes ids, overseas.id
    refute_includes ids, ja_labeled.id
    refute_includes ids, excluded.id
    refute_includes ids, unpublished.id
    refute_includes ids, no_code.id
    refute_includes ids, generation.id
    refute_includes ids, generation_ja_column.id
    assert_equal CrawlPolicy::CRAWLABLE_GENRE_KEYS, CrawlPolicy.crawlable_genre_values
  end

  test "column_path prefixes English articles and stays Japanese without language" do
    ja = create_published!(code: "sm-ja-path-#{SecureRandom.hex(3)}", language: "ja")
    en = create_published!(code: "sm-en-path-#{SecureRandom.hex(3)}", language: "en")
    without_language = Column.select(:id, :code).find(ja.id)

    overseas = create_published!(
      code: "sm-os-path-#{SecureRandom.hex(3)}",
      genre: CrawlPolicy::OVERSEAS_SEO_GENRE_KEY,
      language: "ja"
    )

    assert_equal "/#{CrawlPolicy::GENRE_KEY}/columns/#{ja.code}", CrawlPolicy.column_path(ja)
    assert_equal "/#{CrawlPolicy::OVERSEAS_SEO_GENRE_KEY}/columns/#{overseas.code}", CrawlPolicy.column_path(overseas)
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
    assert_includes xml, "https://drafity.pro/#{CrawlPolicy::OVERSEAS_SEO_GENRE_KEY}/columns</loc>"
    assert_includes xml, "https://drafity.pro#{CrawlPolicy::OVERSEAS_SEO_PATH}</loc>"
    assert_includes xml, "https://drafity.pro#{CrawlPolicy.column_path(column)}</loc>"
    refute_includes xml, "This XML file does not appear to have any style information"
    refute CrawlableSitemap::SITEMAP_PATH.to_s.start_with?(Rails.public_path.to_s)

    loc_count = xml.scan("<loc>").size
    assert_equal CrawlPolicy::STATIC_PATHS.size + CrawlPolicy.crawlable_columns.count, loc_count
  end

  test "article lastmod uses content_updated_at and static pages omit lastmod" do
    older = create_published!(
      title: "古い記事",
      body: "# 古い見出し\n\n本文",
      code: "sm-old-#{SecureRandom.hex(3)}"
    )
    newer = create_published!(
      title: "新しい記事",
      body: "# 新しい見出し\n\n本文",
      code: "sm-new-#{SecureRandom.hex(3)}"
    )
    older.update_columns(content_updated_at: Time.zone.parse("2020-01-15 09:00:00"))
    newer.update_columns(content_updated_at: Time.zone.parse("2024-06-02 08:00:00"))

    CrawlableSitemap.refresh!
    urls = sitemap_url_lastmods(CrawlableSitemap::SITEMAP_PATH.read)
    host = CrawlPolicy::SITEMAP_HOST

    assert_includes urls.fetch("#{host}#{CrawlPolicy.column_path(older)}"), "2020-01-15"
    assert_includes urls.fetch("#{host}#{CrawlPolicy.column_path(newer)}"), "2024-06-02"
    refute_equal urls["#{host}#{CrawlPolicy.column_path(older)}"], urls["#{host}#{CrawlPolicy.column_path(newer)}"]

    assert urls.key?(host)
    assert_nil urls[host]
    assert_nil urls["#{host}#{CrawlPolicy::SEO_CHECKER_PATH}"]

    expected = CrawlableSitemap.listing_lastmod(CrawlPolicy::GENRE_KEY, "ja")
    index_lastmod = urls.fetch("#{host}/#{CrawlPolicy::GENRE_KEY}/columns")
    assert_includes index_lastmod, expected.in_time_zone.strftime("%Y-%m-%d")
  end

  def sitemap_url_lastmods(xml)
    document = Nokogiri::XML(xml)
    document.remove_namespaces!
    document.css("url").each_with_object({}) do |node, result|
      result[node.at_css("loc").text] = node.at_css("lastmod")&.text
    end
  end
end
