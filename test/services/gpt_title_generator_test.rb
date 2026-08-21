# frozen_string_literal: true

require "test_helper"

class GptTitleGeneratorTest < ActiveSupport::TestCase
  test "prompt asks for distinct search intents instead of parent paraphrases" do
    pillar = Column.new(
      title: "Amazon配送の人材不足・採用改善 完全ガイド",
      genre: "cargo",
      article_type: "pillar"
    )
    prompt = GptTitleGenerator.build_titles_prompt(
      pillar,
      count: 8,
      existing_titles: ["既存の子タイトル"],
      sibling_pillar_titles: ["別ピラーのタイトル"]
    )

    assert_includes prompt, "言い換え"
    assert_includes prompt, "最大8個"
    assert_includes prompt, "既存の子タイトル"
    assert_includes prompt, "別ピラーのタイトル"
    refute_includes prompt, "15個から25個"
    refute_includes prompt, "類似の許可"
    refute_includes prompt, "100%合致"
  end

  test "resolve_count never exceeds max intent slots" do
    pillar = Column.new(title: "親")

    assert_equal 10, GptTitleGenerator.resolve_count(pillar, 25)
    assert_equal 3, GptTitleGenerator.resolve_count(pillar, 3)
    assert_equal 0, GptTitleGenerator.resolve_count(pillar, 0)
    assert_equal 10, GptTitleGenerator.resolve_count(pillar, nil)
  end

  test "drops titles that paraphrase the parent or each other" do
    pillar = Column.new(
      title: "軽貨物パートナーの選び方完全ガイド",
      genre: "unique_genre_for_title_gen_test"
    )
    plans = [
      { "intent" => "言い換え", "title" => "軽貨物パートナーの選び方完全ガイド" },
      { "intent" => "選定", "title" => "失敗しない軽貨物パートナー選定5つのポイント" },
      { "intent" => "重複", "title" => "失敗しない軽貨物パートナー選定5つのポイント" },
      { "intent" => "料金", "title" => "軽貨物委託の料金相場と距離制・時間制の違い" }
    ]

    kept = GptTitleGenerator.drop_overlapping_titles(plans, pillar).map { |plan| plan["title"] }

    assert_equal [
      "失敗しない軽貨物パートナー選定5つのポイント",
      "軽貨物委託の料金相場と距離制・時間制の違い"
    ], kept
  end
end
