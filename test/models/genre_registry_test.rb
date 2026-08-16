# frozen_string_literal: true

require "test_helper"

class GenreRegistryTest < ActiveSupport::TestCase
  # fixtures の UNIQUE 衝突を避ける（本テストは DB fixture 不要）
  def setup_fixtures; end
  def teardown_fixtures; end

  setup do
    GenreRegistry.reset!
  end

  teardown do
    GenreRegistry.reset!
  end

  test "resolve_sub_category_key prefers saved driver_recruitment over Amazon配送 keyword match" do
    column = Column.new(
      title: "Amazon配送の軽貨物ドライバーの働き方と収入",
      genre: "cargo",
      sub_genre: "driver_recruitment",
      keyword: "Amazon配送 ドライバー 収入"
    )

    assert_equal "driver_recruitment",
                 GenreRegistry.resolve_sub_category_key(column, "cargo")
  end

  test "resolve_sub_category_key falls back to keyword detection when sub_genre blank" do
    column = Column.new(
      title: "Amazon配送のドライバー採用を強化したい企業向けガイド",
      genre: "cargo",
      sub_genre: nil,
      keyword: "Amazon配送 ドライバー採用"
    )

    assert_equal "delivery_partner",
                 GenreRegistry.resolve_sub_category_key(column, "cargo")
  end

  test "resolve_sub_category_key ignores invalid saved sub_genre and falls back" do
    column = Column.new(
      title: "Amazon配送のドライバー採用を強化したい企業向けガイド",
      genre: "cargo",
      sub_genre: "not_a_real_sub",
      keyword: "Amazon配送 ドライバー採用"
    )

    assert_equal "delivery_partner",
                 GenreRegistry.resolve_sub_category_key(column, "cargo")
  end

  test "service_profile includes driver recruitment target when sub_genre is set" do
    profile = GenreRegistry.service_profile("cargo", "driver_recruitment")

    assert_includes profile, "Amazonの配送員として働きたい個人・求職者"
    assert_not_includes profile, "ドライバー確保に課題がある企業"
  end

  test "column service_profile passes sub_genre" do
    column = Column.new(genre: "cargo", sub_genre: "driver_recruitment")

    assert_includes column.service_profile, "Amazonの配送員として働きたい個人・求職者"
  end

  test "sub_category_label uses name_en for English locale" do
    assert_equal "Routine cleaning",
                 GenreRegistry.sub_category_label("cleaning", "daily_standard", locale: :en)
    assert_equal "日常清掃",
                 GenreRegistry.sub_category_label("cleaning", "daily_standard", locale: :ja)
  end

  test "cargo fallback includes a stock image file that exists" do
    images = GenreRegistry::FALLBACK_GENRES.dig(:cargo, :images)
    assert_includes images, "stock/cargo.jpg"
    assert File.exist?(Rails.root.join("app/assets/images/stock/cargo.jpg"))
  end

  test "fallback templates for admin are labels only and do not copy the full registry" do
    templates = GenreRegistry.fallback_templates_for
    assert templates[:cleaning].key?(:ja)
    refute templates[:cleaning].key?(:sub_categories)
    assert_equal "清掃", GenreRegistry::FALLBACK_GENRES.dig(:cleaning, :ja)
  end
end
