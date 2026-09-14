# frozen_string_literal: true

require "test_helper"

class GptPromptPackTest < ActiveSupport::TestCase
  test "missing prompt raises with relative path" do
    error = assert_raises(ArgumentError) { GptPromptPack.for("ja").render("article") }
    assert_includes error.message, "config/gpt_prompts/ja.yml#article"
  end

  test "there are exactly three language prompt files" do
    files = GptPromptPack::ROOT.glob("*.yml").map { |path| path.basename.to_s }.sort
    assert_equal %w[en.yml hiragana.yml ja.yml], files
  end

  test "english wrap injects the neutralized task" do
    rendered = GptPromptPack.for("en").render("wrap", task: "Write about payroll.")
    assert_includes rendered, "Write the entire response in English"
    assert_includes rendered, "Write about payroll."
  end

  test "japanese pillar prompts load from ja.yml" do
    column = Column.new(title: "テストタイトル", prompt: "追加指示です")
    genre_data = { ja: "物流", keywords: %w[配送 倉庫] }
    sub_data = { target: "荷主", description: "説明", features: %w[特徴A], industry_weakness: "課題" }
    eeat = "EEATテスト"
    fixture_dir = Rails.root.join("test/fixtures/gpt_prompts")

    assert_equal File.read(fixture_dir.join("pillar_introduction.txt")),
                 GptPillarGenerator.introduction_prompt(column, "物流", genre_data, sub_data, eeat)
    assert_equal File.read(fixture_dir.join("pillar_meta.txt")),
                 GptPillarGenerator.meta_prompt(column, "物流", genre_data, sub_data, eeat)
    assert_equal File.read(fixture_dir.join("pillar_structure.txt")),
                 GptPillarGenerator.structure_prompt(column, "物流", genre_data, sub_data, eeat, ["子記事A", "子記事B"])
  end
end
