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

  test "failed_output? detects japanese section failures and job dumps" do
    assert GptGenerationLocale.failed_output?("（導入の本文生成に失敗しました。再生成してください。）")
    assert GptGenerationLocale.failed_output?("（生成エラーにより本文生成に失敗しました）")
    assert GptGenerationLocale.failed_output?("❌ 失敗: RuntimeError - 本文の生成に失敗しました\n場所: job.rb:54")
    assert GptGenerationLocale.failed_output?("")
    refute GptGenerationLocale.failed_output?("現場では責任分界を契約書に落とす。")
  end

  test "gpt-5 payloads omit temperature" do
    payload = GptGenerationLocale.chat_completions_payload(
      model: "gpt-5.4-nano",
      messages: [{ role: "user", content: "hi" }],
      temperature: 0.45
    )
    refute payload.key?(:temperature)

    mini = GptGenerationLocale.chat_completions_payload(
      model: "gpt-4o-mini",
      messages: [{ role: "user", content: "hi" }],
      temperature: 0.45
    )
    assert_equal 0.45, mini[:temperature]
  end

  test "blank language falls back to japanese" do
    assert_equal "ja", Column.normalize_language(nil)
    assert_equal "ja", Column.normalize_language("fr")
    assert_equal "hiragana", Column.normalize_language("hiragana")
    refute Column.new(language: nil).english_article?
    assert Column.new(language: "hiragana").hiragana_article?
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

  test "hiragana does not load a generation prompt and still rewrites the contents heading" do
    prompt = "全て日本語で書いてください。## 目次 を入れてください。健康保険について。"

    GptGenerationLocale.with_language(Column.new(language: "hiragana")) do
      assert_equal "hiragana", GptGenerationLocale.current
      assert_equal prompt, GptGenerationLocale.prepare_user_prompt(prompt)
      assert_equal "通常システム", GptGenerationLocale.resolve_system_prompt("通常システム", json_mode: false)
      assert_equal "通常", GptGenerationLocale.resolve_title_system_prompt("通常")
      assert_equal "もくじ", GptGenerationLocale.toc_heading
    end

    body = "はじめに\n\n## 目次\n\n- A\n"
    rewritten = GptGenerationLocale.rewrite_structure_headings(body, language: "hiragana")
    assert_includes rewritten, "## もくじ"
    refute_includes rewritten, "## 目次"
  end

  test "hiragana markdown puts glued headings onto their own lines" do
    glued = "せつめいします。## もくじ\n- やくわり## やくわり"
    rewritten = GptGenerationLocale.rewrite_structure_headings(glued, language: "hiragana")

    assert_includes rewritten, "せつめいします。\n\n## もくじ"
    assert_match(/^## やくわり/, rewritten.lines.grep(/^## /).last)
    refute_includes rewritten, "します。## もくじ"
  end

  test "hiragana markdown inserts a blank line before headings for kramdown" do
    text = "さいごのぶんです。\n## もくじ\n- やくわり\n## やくわり\nないようです。"
    rewritten = GptGenerationLocale.normalize_hiragana_markdown(text)

    assert_includes rewritten, "さいごのぶんです。\n\n## もくじ\n"
    assert_includes rewritten, "## もくじ\n\n- やくわり"
    assert_includes rewritten, "- やくわり\n\n## やくわり\n"
    html = Kramdown::Document.new(rewritten).to_html
    assert_equal 2, html.scan(/<h2/).size
  end

  test "hiragana rewrite prompt is not available" do
    error = assert_raises(ArgumentError) { GptGenerationLocale.kanji_rewrite_user_prompt("健康保険") }
    assert_equal "ひらがなプロンプトはありません", error.message
  end

  test "language-locked prompts skip wrap overlays" do
    locked = "LANGUAGE: ひらがなのみ。\n本文だけ"

    GptGenerationLocale.with_language(Column.new(language: "hiragana")) do
      assert_equal locked, GptGenerationLocale.prepare_user_prompt(locked)
    end
  end

  test "prompt files are split by language" do
    refute GptPromptPack.for("ja").exist?("wrap")
    refute GptPromptPack.for("ja").exist?("article")
    assert GptPromptPack.for("ja").exist?("system")
    assert GptPromptPack.for("ja").exist?("introduction")
    assert GptPromptPack.for("ja").exist?("title_system")

    assert GptPromptPack.for("en").exist?("wrap")
    assert GptPromptPack.for("en").exist?("system")

    refute GptPromptPack::ROOT.join("hiragana.yml").exist?
    refute GptPromptPack.for("ja").exist?("child_titles")
    refute GptPromptPack.for("ja").exist?("parent_titles")
    refute GptPromptPack.for("en").exist?("child_titles")
    refute GptPromptPack.for("en").exist?("parent_titles")
  end
end
