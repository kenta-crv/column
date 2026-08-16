# frozen_string_literal: true

require "test_helper"
require "json"

class EnglishArticleGenerationPipelineTest < ActiveSupport::TestCase
  def english_column
    Column.new(
      id: 1025,
      title: "The Ultimate Guide to Amazon Delivery: How to Become a Successful Driver",
      language: "en",
      article_type: "pillar",
      genre: "cargo",
      prompt: nil
    )
  end

  test "english wrap removes japanese-only rules from the real pillar introduction prompt" do
    prompt = GptPillarGenerator.introduction_prompt(english_column, "物流", {}, nil, "EEAT")

    assert_includes prompt, "- 日本語"

    GptGenerationLocale.with_language(english_column) do
      wrapped = GptGenerationLocale.prepare_user_prompt(prompt)
      system = GptGenerationLocale.resolve_system_prompt("日本語のみ", json_mode: false)

      assert_includes wrapped, "Write the entire response in English"
      refute_match(/(^|\n)\s*-\s*日本語(\s|$)/, wrapped)
      refute_includes wrapped, "全て日本語"
      refute_includes wrapped, "日本語のみ"
      assert_includes system, "English only"
      refute_includes system, "日本語のみ"
    end
  end

  test "english wrap also covers article-generator introduction prompt" do
    prompt = GptArticleGenerator.introduction_prompt(english_column, "物流", {}, nil, "EEAT")

    GptGenerationLocale.with_language(english_column) do
      wrapped = GptGenerationLocale.prepare_user_prompt(prompt)
      refute_includes wrapped, "全て日本語"
      refute_includes wrapped, "日本語のみ"
    end
  end

  test "japanese wrap leaves pillar introduction prompt unchanged" do
    column = Column.new(title: "日本語タイトル", language: "ja")
    prompt = GptPillarGenerator.introduction_prompt(column, "物流", {}, nil, "EEAT")

    GptGenerationLocale.with_language(column) do
      assert_equal prompt, GptGenerationLocale.prepare_user_prompt(prompt)
      assert_includes GptGenerationLocale.resolve_system_prompt("日本語のみ", json_mode: false), "日本語のみ"
    end
  end

  test "pillar generator actually sends english system and user payloads" do
    payloads = capture_gpt_payloads do
      GptGenerationLocale.with_language(english_column) do
        prompt = GptPillarGenerator.introduction_prompt(english_column, "物流", {}, nil, "EEAT")
        GptPillarGenerator.send(:call_gpt_api, prompt, json_mode: false)
      end
    end

    assert_equal 1, payloads.size
    system = payloads.first.dig("messages", 0, "content")
    user = payloads.first.dig("messages", 1, "content")

    assert_includes system, "English only"
    refute_includes system, "日本語のみ"
    assert_includes user, "Write the entire response in English"
    refute_includes user, "日本語のみ"
    refute_match(/(^|\n)\s*-\s*日本語(\s|$)/, user)
  end

  test "body job calls flux after english pillar body is saved" do
    column = Column.create!(
      title: "English pipeline image",
      article_type: "pillar",
      genre: CrawlPolicy::GENRE_KEY,
      status: "draft",
      code: "en-img-#{SecureRandom.hex(3)}",
      language: "en"
    )

    flux_called = false
    original_generate = ColumnBodyGenerator.method(:generate!)
    original_flux = FluxImageGeneratorService.method(:generate!)

    ColumnBodyGenerator.define_singleton_method(:generate!) do |col|
      col.update!(body: "English body for pipeline test.", status: "completed")
      :managed
    end
    FluxImageGeneratorService.define_singleton_method(:generate!) do |col|
      flux_called = true
      col.update_column(:file, "column_#{col.id}_abcdefabcdefabcd.webp")
      true
    end

    GenerateColumnBodyJob.perform_now(column.id)

    assert flux_called, "Flux image generation must run after body save"
    assert_equal "column_#{column.id}_abcdefabcdefabcd.webp", column.reload[:file]
    assert_equal "en", column.language
  ensure
    ColumnBodyGenerator.define_singleton_method(:generate!, original_generate) if original_generate
    FluxImageGeneratorService.define_singleton_method(:generate!, original_flux) if original_flux
  end

  test "body job does not regenerate an existing pillar body" do
    column = Column.create!(
      title: "Already generated",
      article_type: "pillar",
      genre: CrawlPolicy::GENRE_KEY,
      status: "completed",
      code: "en-skip-#{SecureRandom.hex(3)}",
      language: "en",
      body: "既存の日本語本文"
    )

    generate_called = false
    original_generate = ColumnBodyGenerator.method(:generate!)
    original_flux = FluxImageGeneratorService.method(:generate!)

    ColumnBodyGenerator.define_singleton_method(:generate!) do |_col|
      generate_called = true
      :managed
    end
    FluxImageGeneratorService.define_singleton_method(:generate!) do |_col|
      true
    end

    GenerateColumnBodyJob.perform_now(column.id)

    refute generate_called, "existing pillar body must not be overwritten by the job"
    assert_equal "既存の日本語本文", column.reload.body
  ensure
    ColumnBodyGenerator.define_singleton_method(:generate!, original_generate) if original_generate
    FluxImageGeneratorService.define_singleton_method(:generate!, original_flux) if original_flux
  end

  private

  def capture_gpt_payloads
    payloads = []
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) do |*_args, **_kwargs, &block|
      http = Object.new
      http.define_singleton_method(:request) do |req|
        payloads << JSON.parse(req.body)
        response = Net::HTTPOK.new("1.1", "200", "OK")
        response.instance_variable_set(:@read, true)
        response.define_singleton_method(:body) do
          { choices: [{ message: { content: "Hello from stub." } }] }.to_json
        end
        response
      end
      block.call(http)
    end

    yield
    payloads
  ensure
    Net::HTTP.define_singleton_method(:start, original)
  end
end
