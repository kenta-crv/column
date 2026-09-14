# frozen_string_literal: true

require "test_helper"
require "json"

class PillarTitleSuggestionServiceTest < ActiveSupport::TestCase
  def prompt_locals(language:)
    {
      language: language,
      keyword1: "住民票",
      keyword2: "登録",
      target_layer: "middle",
      genre_label: "物流",
      sub_genre_label: nil,
      service_info: "配送",
      custom_prompt: nil,
      title_count: 2
    }
  end

  test "japanese parent-title prompt stays on the original Japanese copy" do
    prompt = PillarTitleSuggestionService.build_prompt(**prompt_locals(language: "ja"))

    assert_includes prompt, "あなたの役割"
    assert_includes prompt, "魅力的な日本語として成立させる"
    assert_includes prompt, "住民票"
    assert_includes prompt, "2個"
    refute_includes prompt, "LANGUAGE: ひらがなのみ"
    refute_includes prompt, "Your role"
  end

  test "english parent-title prompt still uses the Japanese source task" do
    prompt = PillarTitleSuggestionService.build_prompt(**prompt_locals(language: "en"))

    assert_includes prompt, "あなたの役割"
    assert_includes prompt, "魅力的な日本語として成立させる"
    refute_includes prompt, "LANGUAGE: ひらがなのみ"
  end

  test "hiragana uses a dedicated parent-title prompt instead of wrapping Japanese" do
    prompt = PillarTitleSuggestionService.build_prompt(**prompt_locals(language: "hiragana"))

    assert_includes prompt, "LANGUAGE: ひらがなのみ"
    assert_includes prompt, "漢字ゼロ"
    assert_includes prompt, "住民票"
    assert_includes prompt, "2本"
    refute_includes prompt, "あなたの役割"
    refute_includes prompt, "魅力的な日本語として成立させる"
    refute_includes prompt, "下のタスクは通常の日本語記事向け"
    refute_includes prompt, "本文に「## もくじ」"
    refute_includes prompt, "Your role"
  end

  test "hiragana parent-title request sends dedicated system and user payloads" do
    payloads = []
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) do |*_args, **_kwargs, &block|
      http = Object.new
      http.define_singleton_method(:request) do |req|
        payloads << JSON.parse(req.body)
        response = Net::HTTPOK.new("1.1", "200", "OK")
        response.instance_variable_set(:@read, true)
        response.define_singleton_method(:body) do
          {
            choices: [{
              message: {
                content: { titles: [{ title: "じゅうみんひょうのとうろく" }] }.to_json
              }
            }]
          }.to_json
        end
        response
      end
      block.call(http)
    end

    result = PillarTitleSuggestionService.call(
      keyword1: "住民票",
      keyword2: "登録",
      target_layer: "middle",
      genre: "cargo",
      suggestion_count: 1,
      language: "hiragana"
    )
    system = payloads.first.dig("messages", 0, "content")
    user = payloads.first.dig("messages", 1, "content")

    assert result[:success]
    assert_equal ["じゅうみんひょうのとうろく"], result[:titles]
    assert_equal 1, payloads.size
    assert_includes system, "漢字は一文字も使わず"
    assert_includes user, "LANGUAGE: ひらがなのみ"
    assert_includes user, "住民票"
    refute_includes user, "あなたの役割"
    refute_includes user, "下のタスクは通常の日本語記事向け"
  ensure
    Net::HTTP.define_singleton_method(:start, original)
  end
end
