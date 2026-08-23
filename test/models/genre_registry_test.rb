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

    assert_includes profile, "日本で働きたい外国人、すでに在留している求職者"
    assert_not_includes profile, "外国人ドライバーの確保・定着に課題がある企業"
  end

  test "column service_profile passes sub_genre" do
    column = Column.new(genre: "cargo", sub_genre: "driver_recruitment")

    assert_includes column.service_profile, "日本で働きたい外国人、すでに在留している求職者"
  end

  test "service_profile for foreign_hiring is employer-facing" do
    profile = GenreRegistry.service_profile("cargo", "foreign_hiring")

    assert_includes profile, "外国人材の採用・受け入れを検討している企業"
    assert_includes profile, "外国人雇用"
  end

  test "cargo main genre label is 外国人" do
    assert_equal "外国人", GenreRegistry::FALLBACK_GENRES.dig(:cargo, :ja)
    assert_equal "Amazon外国人配送",
                 GenreRegistry::FALLBACK_GENRES.dig(:cargo, :sub_categories, :delivery_partner, :name)
    %i[life_guide specified_skills support_orgs labor_help].each do |key|
      assert GenreRegistry::FALLBACK_GENRES.dig(:cargo, :sub_categories, key).present?, key.to_s
    end
  end

  test "specified_skills keyword wins over foreign_hiring" do
    column = Column.new(
      title: "特定技能の受け入れ機関がやるべきこと",
      genre: "cargo",
      sub_genre: nil,
      keyword: "特定技能 登録支援機関"
    )

    assert_equal "specified_skills",
                 GenreRegistry.resolve_sub_category_key(column, "cargo")
  end

  test "life_guide keyword detection" do
    column = Column.new(
      title: "来日後の住民登録とマイナンバー",
      genre: "cargo",
      sub_genre: nil,
      keyword: "住民登録 マイナンバー"
    )

    assert_equal "life_guide",
                 GenreRegistry.resolve_sub_category_key(column, "cargo")
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
