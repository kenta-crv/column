# frozen_string_literal: true

# 記事生成の出力言語。日本語プロンプトは既存のまま残し、
# language=en のときだけ英語システムプロンプトとユーザー指示を使う。
module GptGenerationLocale
  module_function

  def with_language(column)
    previous = Thread.current[:gpt_generation_language]
    Thread.current[:gpt_generation_language] = Column.normalize_language(column.try(:language))
    Rails.logger.info(
      "[GptGenerationLocale] column_id=#{column.try(:id)} language=#{current}"
    )
    yield
  ensure
    Thread.current[:gpt_generation_language] = previous
  end

  def current
    Column.normalize_language(Thread.current[:gpt_generation_language])
  end

  def english?
    current == "en"
  end

  TOC_HEADING_JA = "目次"
  TOC_HEADING_EN = "Contents"
  TOC_HEADINGS = [TOC_HEADING_JA, TOC_HEADING_EN].freeze

  def toc_heading
    english? ? TOC_HEADING_EN : TOC_HEADING_JA
  end

  def toc_heading?(text)
    TOC_HEADINGS.include?(text.to_s.gsub(/[#\s　]/, ""))
  end

  def rewrite_structure_headings(body, language: current)
    text = body.to_s
    return text unless Column.english_language?(language)

    text.sub(/^##[[:space:]]*目次[[:space:]]*$/, "## #{TOC_HEADING_EN}")
        .gsub(/^##[[:space:]]*まとめ[[:space:]]*$/, "## Conclusion")
  end

  def prepare_user_prompt(prompt)
    return prompt unless english?

    task = neutralize_japanese_output_instructions(prompt.to_s)

    <<~EN
      LANGUAGE: Write the entire response in English.
      The task below was originally written for Japanese articles. Override every Japanese-output rule.
      JSON string values (description, keyword, h2_title, captions, titles) must be English.
      If the task says to start with "## まとめ", start with "## Conclusion" instead.
      Use "## Contents" for the table of contents heading, never the Japanese equivalent.
      Character counts in 文字 are Japanese-density targets. For English, write roughly 45–55% as many words as that number (900文字 ≈ 400–500 words). Do not output a short English stub of only 900 characters.

      Genre / EEAT facts below may be in Japanese. Treat them as source facts and express them in English. Do not mix Japanese into the article body.

      --- Task ---
      #{task}
    EN
  end

  def neutralize_japanese_output_instructions(text)
    text.to_s
      .gsub("全て日本語", "English only")
      .gsub("すべて日本語", "English only")
      .gsub("日本語のみで出力", "output in English only")
      .gsub("日本語のみ", "English only")
      .gsub("日本語で出力", "output in English")
      .gsub("日本語で書く", "write in English")
      .gsub("日本語で書け", "write in English")
      .gsub("日本語説明", "English explanation")
      .gsub("## 目次", "## Contents")
      .gsub("## まとめ", "## Conclusion")
      .gsub(/(^|\n)(\s*[-*]\s*)日本語(\s*)(?=\n|$)/, '\1\2English\3')
  end

  def resolve_system_prompt(japanese_system, json_mode:)
    return japanese_system unless english?

    system_content = <<~SYSTEM
      You are a professional SEO / editorial writer.

      CRITICAL RULES
      - English only
      - Neutral, practical explanation — not a sales page or roundup-affiliate article
      - No hype, no fabricated anecdotes
      - Explain industry structure from primary-source style facts
      - Avoid AI-sounding filler, rigid PREP templates, and bullet-point spam
      - Do not start sections with "In this article" / "This article will"
      - Do not overuse "recommended"
      - Follow Google E-E-A-T
      - Do not restate another section's conclusion; add a new angle
      - Use Markdown tables/checklists only when the user task asks for them
      - Vary sentence endings; do not repeat the same wrap-up phrase twice in one section
      - Follow the user task's genre (SEO guide, comparison, essay, Qiita/Zenn-style technical post) in English
    SYSTEM

    if json_mode
      system_content + "\nOutput JSON only."
    else
      system_content + "\nOutput body text only.\nNo JSON.\nNo extra headings unless the task asks for them."
    end
  end

  def resolve_title_system_prompt(japanese_system)
    return japanese_system unless english?

    "You are an SEO consultant. Return only a JSON object in the specified format. No markdown fences, backticks, or commentary. All title strings must be in English."
  end

  def min_length(japanese_min)
    return japanese_min unless english?

    (japanese_min.to_i * 1.8).to_i
  end

  def extract_gist(section_body)
    return "" if section_body.blank?

    if english?
      sentences = section_body.split(/(?<=[.!?])\s+/).map(&:strip).reject(&:blank?)
      sentences.last(2).join(" ").truncate(220)
    else
      sentences = section_body.split(/(?<=。)/).map(&:strip).reject(&:blank?)
      sentences.last(2).join("").truncate(180)
    end
  end

  def failed_output?(text)
    value = text.to_s
    value.include?("生成失敗") || value.downcase.include?("generation failed")
  end

  def section_failure_message(name)
    if english?
      "(Body generation failed for #{name}. Please regenerate.)"
    else
      "（#{name}の本文生成に失敗しました。再生成してください。）"
    end
  end
end
