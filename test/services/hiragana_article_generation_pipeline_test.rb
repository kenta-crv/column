# frozen_string_literal: true

require "test_helper"
require "json"

class HiraganaArticleGenerationPipelineTest < ActiveSupport::TestCase
  def hiragana_column
    Column.new(
      id: 1026,
      title: "じゅうみんひょうのとうろく",
      language: "hiragana",
      article_type: "pillar",
      genre: "cargo",
      prompt: nil
    )
  end

  test "hiragana wrap bans kanji and rewrites toc heading in user prompt" do
    prompt = GptPillarGenerator.introduction_prompt(hiragana_column, "物流", {}, nil, "EEAT")

    GptGenerationLocale.with_language(hiragana_column) do
      wrapped = GptGenerationLocale.prepare_user_prompt(prompt)
      system = GptGenerationLocale.resolve_system_prompt("日本語のみ", json_mode: false)

      assert_equal "hiragana", GptGenerationLocale.current
      assert GptGenerationLocale.hiragana?
      assert_includes wrapped, "漢字は禁止"
      assert_includes wrapped, "本文に「## もくじ」や「## 目次」は書かない"
      refute_includes wrapped, "全て日本語"
      refute_match(/(^|\n)\s*-\s*日本語(\s|$)/, wrapped)
      assert_includes wrapped, "「。」と「、」を使う"
      assert_includes system, "漢字は一文字も使わない"
      refute_equal "日本語のみ", system
      assert_equal "もくじ", GptGenerationLocale.toc_heading
    end
  end

  test "hiragana wrap also covers article-generator introduction prompt" do
    prompt = GptArticleGenerator.introduction_prompt(hiragana_column, "物流", {}, nil, "EEAT")

    GptGenerationLocale.with_language(hiragana_column) do
      wrapped = GptGenerationLocale.prepare_user_prompt(prompt)
      assert_includes wrapped, "漢字は禁止"
      assert_includes wrapped, "LANGUAGE: ひらがなのみ"
    end
  end

  test "rewrite_structure_headings maps 目次 to もくじ for hiragana" do
    body = "はじめに\n\n## 目次\n\n- A\n\n## Contents\n"
    rewritten = GptGenerationLocale.rewrite_structure_headings(body, language: "hiragana")

    assert_includes rewritten, "## もくじ"
    refute_includes rewritten, "## 目次"
    refute_includes rewritten, "## Contents"
  end

  test "hiragana articles use a dedicated short-article prompt" do
    prompt = GptHiraganaArticleGenerator.build_article_prompt(hiragana_column)

    assert_includes prompt, "LANGUAGE: ひらがなのみ"
    assert_includes prompt, "漢字ゼロ"
    assert_includes prompt, "単語を空白で区切らない"
    assert_includes prompt, "1200〜1800字"
    assert_includes prompt, "じゅうみんひょうのとうろく"
    assert_includes prompt, "本文に ## もくじ は書かない"
    assert_includes prompt, "pillar のとき"
    assert_includes prompt, "タイトルを # や ## でくり返さない"
    assert_includes prompt, "見出しの末尾に「。」をつけない"
    assert_includes prompt, "えいごのキー"
    assert_includes prompt, "いきなり ## では始めない"
    refute_includes prompt, "キーワードを空白区切り"
    refute_includes prompt, "つぎに独立した行で ## もくじ"
    refute_includes prompt, "700〜1100文字"
    refute_includes prompt, "下のタスクは通常の日本語記事向け"
  end

  test "hiragana article prompt does not dump english sub_genre keys as facts" do
    column = Column.new(
      title: "ビザのしゅるいごとに、はたらけるしごと",
      language: "hiragana",
      article_type: "pillar",
      genre: "cargo",
      sub_genre: "driver_recruitment",
      keyword: "ビザ しごと"
    )
    prompt = GptHiraganaArticleGenerator.build_article_prompt(column)

    refute_includes prompt, "ジャンル: cargo"
    refute_includes prompt, "中分類キー"
    refute_includes prompt, "ビザ しごと"
    assert_includes prompt, "ビザ、しごと"
  end

  test "normalize strips h1 without space and kana gaps" do
    payload = {
      "body" => "#たいとる\n\nりゅうがくせい は アルバイトができます。\n"
    }
    normalized = GptHiraganaArticleGenerator.send(:normalize_payload, payload)

    refute_match(/\A#/, normalized["body"])
    assert_includes normalized["body"], "りゅうがくせいはアルバイトができます。"
  end

  test "normalize prepends title lead when body starts with heading" do
    payload = { "body" => "## きょかをみる\n\nざいりゅうかーどをみます。\n" }
    column = Column.new(title: "りゅうがくせいがアルバイトできるのは、きょかがあるとき｜1しゅうかんは28じかんまで")
    normalized = GptHiraganaArticleGenerator.send(:normalize_payload, payload, column: column)

    assert_match(/\Aりゅうがくせいがアルバイトできるのは、きょかがあるとき。/, normalized["body"])
    assert_includes normalized["body"], "## きょかをみる"
  end

  test "summary restating a section is not treated as duplication" do
    body = <<~MD
      ## きょかをみる
      ざいりゅうかーどをみます。きょかがあるとかきます。こうしきのページでもみます。
      ## まとめ
      ざいりゅうかーどをみます。きょかがあるとかきます。こうしきのページでもみます。
    MD

    assert_nil GptHiraganaArticleGenerator.send(:duplicated_section, body)
  end

  test "source facts omit extra prompt and squeeze keyword spaces" do
    column = Column.new(
      title: "テスト",
      language: "hiragana",
      keyword: "りゅうがくせい アルバイト",
      prompt: "にほんで はたらきたい"
    )
    facts = GptHiraganaArticleGenerator.send(:source_facts_for, column)

    assert_includes facts, "りゅうがくせい、アルバイト"
    refute_includes facts, "にほんで はたらきたい"
  end

  test "column body generator routes hiragana to the dedicated generator" do
    assert_equal GptHiraganaArticleGenerator, ColumnBodyGenerator.service_class_for(hiragana_column)
  end

  test "pillar generator actually sends hiragana system and user payloads" do
    payloads = capture_gpt_payloads do
      GptGenerationLocale.with_language(hiragana_column) do
        prompt = GptPillarGenerator.introduction_prompt(hiragana_column, "物流", {}, nil, "EEAT")
        GptPillarGenerator.send(:call_gpt_api, prompt, json_mode: false)
      end
    end

    assert_equal 1, payloads.size
    system = payloads.first.dig("messages", 0, "content")
    user = payloads.first.dig("messages", 1, "content")

    assert_includes system, "漢字は一文字も使わない"
    assert_includes user, "LANGUAGE: ひらがなのみ"
    assert_includes user, "漢字は禁止"
  end

  test "mecab converts 入管 and okurigana without asking GPT" do
    skip "MeCab is not installed" unless GptHiraganaArticleGenerator::MecabReadingConverter.available?

    converted = GptHiraganaArticleGenerator::MecabReadingConverter.convert(
      "入管に行きます。決まった。在留カードを見る。"
    )

    assert_equal "にゅうかんにいきます。きまった。ざいりゅうカードをみる。", converted

    heading = GptHiraganaArticleGenerator::MecabReadingConverter.convert("## 在留資格について")
    assert_equal "## ざいりゅうしかくについて", heading

    japan = GptHiraganaArticleGenerator::MecabReadingConverter.convert("日本で入国管理局へ行く。")
    assert_equal "にほんでにゅうかんへいく。", japan
    refute_includes japan, "にっぽん"
    refute_includes japan, "にゅうこくかんり"
  end

  test "article prompt no longer asks GPT for readings" do
    pack = GptPromptPack.for("hiragana")

    refute pack.exist?("readings_request")
    article = pack.render("article", title: "t", article_type: "pillar", source_facts: "なし", extra_prompt: "なし")
    assert_includes article, "読みはあとで辞書が付けます"
    refute_includes article, "在留カード → 1週間の時間 → 入管のページ"
    assert_includes pack.render("proofread", text: "あ", source_facts: "なし"), "よみは辞書で変換済み"
  end

  test "validate rejects banned readings and missing h3" do
    column = Column.new(title: "ビザのしゅるい", keyword: "ビザ、しごと")
    body = <<~MD
      これはべつのはなしです。これはべつのはなしです。これはべつのはなしです。これはべつのはなしです。
      ## ひとつ
      ないようです。ないようです。ないようです。ないようです。
      ## ふたつ
      ないようです。ないようです。ないようです。ないようです。
      ## みっつ
      ないようです。ないようです。ないようです。ないようです。
      ## まとめ
      ないようです。ないようです。ないようです。ないようです。
    MD
    nipppon = { "body" => "にっぽんではたらきます。" + body, "description" => "あ", "keyword" => "ビザ" }
    assert_equal "banned reading にっぽん", GptHiraganaArticleGenerator.send(:validate_payload, nipppon, column: column)
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
          { choices: [{ message: { content: "こんにちは。" } }] }.to_json
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
