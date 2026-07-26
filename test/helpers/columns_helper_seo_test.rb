require "test_helper"

class ColumnsHelperSeoTest < ActionView::TestCase
  include ColumnsHelper
  include MetaTags::ViewHelper

  class FakeFile
    def initialize(url)
      @url = url
    end

    def url
      @url
    end

    def to_s
      @url
    end

    def blank?
      @url.blank?
    end

    def present?
      !blank?
    end
  end

  setup do
    @request = ActionDispatch::TestRequest.create
    @request.host = "meetia.pro"
    @request.path = "/columns/sample-article"
  end

  def request
    @request
  end

  def public_request_host
    "meetia.pro"
  end

  test "column_seo_description prefers stored description" do
    column = Column.new(title: "タイトル", description: "専用の説明文です", body: "# 長い本文")
    assert_equal "専用の説明文です", column_seo_description(column)
  end

  test "column_seo_description falls back to body excerpt when description equals title" do
    column = Column.new(title: "タイトル", description: "タイトル", body: "これは本文の抜粋として使われる文章です。" * 3)
    desc = column_seo_description(column)
    assert_includes desc, "これは本文"
    refute_equal "タイトル", desc
  end

  test "column_article_json_ld includes author date and image" do
    column = Column.new(
      title: "AI商談の未来",
      description: "説明文",
      genre: "AI商談代行",
      published_at: Time.zone.parse("2026-07-20 10:00:00"),
      updated_at: Time.zone.parse("2026-07-21 11:00:00")
    )
    column.define_singleton_method(:file) { FakeFile.new("/uploads/column/file/1.jpg") }

    data = JSON.parse(column_article_json_ld(column))
    assert_equal "Article", data["@type"]
    assert_equal "AI商談の未来", data["headline"]
    assert_equal "説明文", data["description"]
    assert_equal "Meetia", data["author"]["name"]
    assert_equal "Meetia", data["publisher"]["name"]
    assert data["datePublished"].present?
    assert_equal ["https://meetia.pro/uploads/column/file/1.jpg"], data["image"]
  end
end
