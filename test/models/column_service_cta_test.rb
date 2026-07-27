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

    genre = ServiceGenre.find_or_initialize_by(key: "meetia", client_id: nil)
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
      default = ColumnServiceCta.default_payload_for("meetia")
      genre.update!(column_cta: ColumnServiceCta.stringify_payload(default)) if default
    end
  end

  test "returns nil for unknown genre" do
    column = Column.new(genre: "unknown_genre_xyz")
    assert_nil ColumnServiceCta.resolve(column)
  end
end
