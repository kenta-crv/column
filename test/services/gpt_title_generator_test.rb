# frozen_string_literal: true

require "test_helper"
require "json"

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

  test "hiragana uses a dedicated child-title prompt instead of wrapping Japanese" do
    pillar = Column.new(
      title: "じゅうみんひょうのとうろく",
      genre: "cargo",
      article_type: "pillar",
      language: "hiragana"
    )
    prompt = GptTitleGenerator.build_titles_prompt(pillar)

    assert_includes prompt, "LANGUAGE: ひらがなのみ"
    assert_includes prompt, "漢字ゼロ"
    assert_includes prompt, "じゅうみんひょうのとうろく"
    assert_includes prompt, "12本"
    assert_includes prompt, '"cluster_titles"'
    assert_includes prompt, "主題（必ずタイトルに入れることば）"
    assert_includes prompt, "でんわやネットでどうやってそうだんするか"
    refute_includes prompt, "最大3本"
    refute_includes prompt, "12〜18本"
    refute_includes prompt, "15〜25本"
    refute_includes prompt, "あなたの役割"
    refute_includes prompt, "魅力的な日本語として成立させる"
    refute_includes prompt, "下のタスクは通常の日本語記事向け"
    refute_includes prompt, "本文に「## もくじ」"
    refute_includes prompt, "Your role"
  end

  test "hiragana title request sends dedicated system and user payloads" do
    pillar = Column.new(
      title: "じゅうみんひょうのとうろく",
      genre: "cargo",
      article_type: "pillar",
      language: "hiragana"
    )
    payloads = []
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) do |*_args, **_kwargs, &block|
      http = Object.new
      http.define_singleton_method(:request) do |req|
        payloads << JSON.parse(req.body)
        response = Net::HTTPOK.new("1.1", "200", "OK")
        response.instance_variable_set(:@read, true)
        response.define_singleton_method(:body) do
          cluster = 8.times.map do |i|
            { title: "じゅうみんひょうのとうろくのてじゅん#{i}", angle: "てじゅん" }
          end
          { choices: [{ message: { content: { cluster_titles: cluster }.to_json } }] }.to_json
        end
        response
      end
      block.call(http)
    end

    titles = GptTitleGenerator.generate_titles(pillar)
    system = payloads.first.dig("messages", 0, "content")
    user = payloads.first.dig("messages", 1, "content")

    assert_equal 1, payloads.size
    assert_equal 8, titles.size
    assert titles.all? { |plan| plan["title"].include?("じゅうみんひょうのとうろく") }
    assert_includes system, "漢字は一文字も使わず"
    assert_includes user, "LANGUAGE: ひらがなのみ"
    assert_includes user, "じゅうみんひょうのとうろく"
    refute_includes user, "あなたの役割"
    refute_includes user, "下のタスクは通常の日本語記事向け"
  ensure
    Net::HTTP.define_singleton_method(:start, original)
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
