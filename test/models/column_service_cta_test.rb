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

  test "resolves ai_sales_agent CTA and keeps meetia theme" do
    column = Column.new(genre: "ai_sales_agent", title: "AI商談の進め方")
    cta = ColumnServiceCta.resolve(column)

    assert_equal "Meetia", cta[:badge]
    assert_equal "/", cta[:path]
    assert_equal "meetia", cta[:theme]
  end

  test "resolves CTA via legacy meetia alias key" do
    column = Column.new(genre: "meetia", title: "AI商談の進め方")
    cta = ColumnServiceCta.resolve(column)

    assert_equal "Meetia", cta[:badge]
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

  test "resolves cargo foreign_hiring CTA" do
    column = Column.new(
      genre: "cargo",
      sub_genre: "foreign_hiring",
      title: "外国人雇用の助成金",
      keyword: "外国人雇用 助成金"
    )
    cta = ColumnServiceCta.resolve(column)

    assert_equal "企業向け", cta[:badge]
    assert_includes cta[:cta_label], "雇用"
  end

  test "resolves life_guide CTA to recruit LINE" do
    column = Column.new(
      genre: "cargo",
      sub_genre: "life_guide",
      title: "住民登録の手続き",
      keyword: "住民登録"
    )
    cta = ColumnServiceCta.resolve(column)

    assert_equal "生活サポート", cta[:badge]
    assert_equal "jwork-recruit", cta[:theme]
  end

  test "resolves specified_skills CTA to employer LINE" do
    column = Column.new(
      genre: "cargo",
      sub_genre: "specified_skills",
      title: "特定技能の受け入れ",
      keyword: "特定技能"
    )
    cta = ColumnServiceCta.resolve(column)

    assert_equal "企業向け", cta[:badge]
    assert_includes cta[:cta_label], "受け入れ"
  end

  test "resolves labor_help CTA" do
    column = Column.new(
      genre: "cargo",
      sub_genre: "labor_help",
      title: "未払い賃金の相談先",
      keyword: "未払い賃金 労働基準監督署"
    )
    cta = ColumnServiceCta.resolve(column)

    assert_equal "相談窓口", cta[:badge]
    assert_equal "jwork-recruit", cta[:theme]
  end

  test "returns nil when stored CTA is disabled" do
    skip "column_cta column missing" unless ServiceGenre.column_names.include?("column_cta")

    genre = ServiceGenre.create!(
      key: "cta_disabled_test",
      ja: "CTA無効テスト",
      service_name: "Test",
      client_id: nil,
      column_cta: {
        "enabled" => false,
        "title" => "非表示タイトル",
        "cta_label" => "ボタン",
        "path" => "/"
      }
    )
    column = Column.new(genre: genre.key, title: "テスト")
    assert_nil ColumnServiceCta.resolve(column)
  ensure
    genre&.destroy
  end

  test "prefers stored ServiceGenre CTA over code default" do
    skip "column_cta column missing" unless ServiceGenre.column_names.include?("column_cta")

    genre = ServiceGenre.find_or_initialize_by(key: "ai_sales_agent", client_id: nil)
    genre.ja ||= "AI商談代行"
    genre.service_name ||= "Meetia"
    genre.column_cta = {
      "enabled" => true,
      "theme" => "meetia",
      "badge" => "MeetiaDB",
      "title" => "DB見出し",
      "cta_label" => "DBボタン",
      "path" => "/plans"
    }
    genre.save!

    column = Column.new(genre: "ai_sales_agent", title: "AI商談")
    cta = ColumnServiceCta.resolve(column)

    assert_equal "MeetiaDB", cta[:badge]
    assert_equal "DB見出し", cta[:title]
    assert_equal "/plans", cta[:path]
  ensure
    if genre&.persisted? && genre.column_cta&.dig("badge") == "MeetiaDB"
      default = ColumnServiceCta.default_payload_for("ai_sales_agent")
      genre.update!(column_cta: ColumnServiceCta.stringify_payload(default)) if default
    end
  end

  test "returns nil for unknown genre" do
    column = Column.new(genre: "unknown_genre_xyz")
    assert_nil ColumnServiceCta.resolve(column)
  end

  test "uses English CTA copy for English articles" do
    column = Column.new(genre: "ai_article", language: "en", title: "AI articles")
    cta = ColumnServiceCta.resolve(column)

    assert_includes cta[:title], "AI article"
    assert_equal "See the service", cta[:cta_label]
    assert_not_includes cta[:title], "加速"
  end

  test "uses English recruit CTA for English cargo driver articles" do
    column = Column.new(
      genre: "cargo",
      sub_genre: "driver_recruitment",
      language: "en",
      title: "Amazon delivery driver jobs",
      keyword: "Amazon delivery driver"
    )
    cta = ColumnServiceCta.resolve(column)

    assert_equal "For job seekers", cta[:badge]
    assert_includes cta[:title], "LINE"
    assert_not_includes cta[:badge], "求職"
    assert_includes cta[:title], "Japan"
  end
end
