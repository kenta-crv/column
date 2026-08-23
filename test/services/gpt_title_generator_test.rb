# frozen_string_literal: true

require "test_helper"

class GptTitleGeneratorTest < ActiveSupport::TestCase
  test "japanese prompt restores tone match and similar-title allowance" do
    pillar = Column.new(
      title: "Amazon配送の人材不足・採用改善 完全ガイド",
      genre: "cargo",
      article_type: "pillar",
      language: "ja"
    )
    prompt = GptTitleGenerator.build_titles_prompt(pillar)

    assert_includes prompt, "合計15〜25本"
    assert_includes prompt, "類似の許可"
    assert_includes prompt, "完全な同調"
    assert_includes prompt, pillar.title
    assert_includes prompt, '"angle"'
    refute_includes prompt, "親の言い換えや、同じ検索意図の量産は禁止"
    refute_includes prompt, "Your role"
  end

  test "english prompt mirrors the new cluster-title workflow" do
    pillar = Column.new(
      title: "Amazon Delivery Driver Shortages: A Complete Guide",
      genre: "cargo",
      article_type: "pillar",
      language: "en"
    )
    prompt = GptTitleGenerator.build_titles_prompt(pillar)

    assert_includes prompt, "Your role"
    assert_includes prompt, "15–25 titles total"
    assert_includes prompt, "similar-but-different angles allowed"
    assert_includes prompt, "Full alignment"
    assert_includes prompt, pillar.title
    assert_includes prompt, '"angle"'
    assert_includes prompt, "All title and angle strings must be in English"
    refute_includes prompt, "あなたの役割"
    refute_includes prompt, "合計15〜25本"
  end

  test "maps exhausted OpenAI credits to a billing message" do
    body = {
      error: {
        message: "You have no credits remaining.",
        type: "insufficient_quota",
        code: "credit_balance_exhausted"
      }
    }.to_json

    assert_equal(
      "OpenAIのAPIクレジットが不足しています。課金設定を確認してください。",
      GptTitleGenerator.user_facing_api_error("429", body)
    )
  end
end
