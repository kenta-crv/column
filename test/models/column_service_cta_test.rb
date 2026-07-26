# frozen_string_literal: true

require "test_helper"

class ColumnServiceCtaTest < ActiveSupport::TestCase
  def setup_fixtures; end
  def teardown_fixtures; end

  setup do
    GenreRegistry.reset!
  end

  teardown do
    GenreRegistry.reset!
  end

  test "resolves meetia CTA for ai_sales_agent alias" do
    column = Column.new(genre: "ai_sales_agent", title: "AI商談の進め方")
    cta = ColumnServiceCta.resolve(column)

    assert_equal "Meetia", cta[:badge]
    assert_equal "/", cta[:path]
    assert_equal "meetia", cta[:theme]
  end

  test "resolves cargo recruit CTA by sub_genre" do
    column = Column.new(
      genre: "cargo",
      sub_genre: "driver_recruitment",
      title: "Amazon配送ドライバーの働き方",
      keyword: "Amazon配送 ドライバー"
    )
    cta = ColumnServiceCta.resolve(column)

    assert_equal "求職者向け", cta[:badge]
    assert_includes cta[:url], "lin.ee"
    assert_equal "jwork-recruit", cta[:theme]
  end

  test "resolves cargo business CTA by default" do
    column = Column.new(
      genre: "cargo",
      sub_genre: "delivery_partner",
      title: "Amazon配送の業務請負",
      keyword: "Amazon配送 業務請負"
    )
    cta = ColumnServiceCta.resolve(column)

    assert_equal "J Work", cta[:badge]
    assert_includes cta[:cta_label], "新規取引"
  end

  test "returns nil for unknown genre" do
    column = Column.new(genre: "unknown_genre_xyz")
    assert_nil ColumnServiceCta.resolve(column)
  end
end
