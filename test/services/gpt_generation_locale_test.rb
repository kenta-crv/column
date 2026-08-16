# frozen_string_literal: true

require "test_helper"

class GptGenerationLocaleTest < ActiveSupport::TestCase
  test "japanese path leaves prompts unchanged" do
    prompt = "全て日本語で書いてください"

    GptGenerationLocale.with_language(Column.new(language: "ja")) do
      assert_equal "ja", GptGenerationLocale.current
      refute GptGenerationLocale.english?
      assert_equal prompt, GptGenerationLocale.prepare_user_prompt(prompt)
      assert_equal "日本語システム", GptGenerationLocale.resolve_system_prompt("日本語システム", json_mode: false)
      assert_equal 600, GptGenerationLocale.min_length(600)
      assert_equal "前段です。末尾です。", GptGenerationLocale.extract_gist("導入です。前段です。末尾です。")
    end
  end

  test "english path wraps user prompt and uses english system" do
    prompt = "全て日本語で書いてください"

    GptGenerationLocale.with_language(Column.new(language: "en")) do
      wrapped = GptGenerationLocale.prepare_user_prompt(prompt)
      assert GptGenerationLocale.english?
      refute_equal prompt, wrapped
      assert_includes wrapped, "Write the entire response in English"
      refute_includes wrapped, "全て日本語"
      assert_includes wrapped, "English only"

      system = GptGenerationLocale.resolve_system_prompt("日本語のみ", json_mode: false)
      assert_includes system, "English only"
      refute_includes system, "日本語のみ"

      assert GptGenerationLocale.min_length(600) > 600
      assert_equal "B. C.", GptGenerationLocale.extract_gist("A. B. C.")
      assert GptGenerationLocale.failed_output?("(Body generation failed for Intro. Please regenerate.)")
    end
  end

  test "blank language falls back to japanese" do
    assert_equal "ja", Column.normalize_language(nil)
    assert_equal "ja", Column.normalize_language("fr")
    refute Column.new(language: nil).english_article?
  end

  test "english articles use Contents instead of 目次" do
    GptGenerationLocale.with_language(Column.new(language: "en")) do
      assert_equal "Contents", GptGenerationLocale.toc_heading
      wrapped = GptGenerationLocale.prepare_user_prompt("## 目次 を入れてください")
      refute_includes wrapped, "目次"
      assert_includes wrapped, "## Contents"
    end

    GptGenerationLocale.with_language(Column.new(language: "ja")) do
      assert_equal "目次", GptGenerationLocale.toc_heading
    end

    body = "Intro\n\n## 目次\n\n- A\n"
    rewritten = GptGenerationLocale.rewrite_structure_headings(body, language: "en")
    assert_includes rewritten, "## Contents"
    refute_includes rewritten, "## 目次"
    assert_equal body, GptGenerationLocale.rewrite_structure_headings(body, language: "ja")
    assert GptGenerationLocale.toc_heading?("目次")
    assert GptGenerationLocale.toc_heading?("Contents")
    refute GptGenerationLocale.toc_heading?("Amazon delivery")
  end
end
