# frozen_string_literal: true

# 記事生成の出力言語。column.language に応じてプロンプトを切り替える。
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

  def hiragana?
    current == "hiragana"
  end

  TOC_HEADING_JA = "目次"
  TOC_HEADING_EN = "Contents"
  TOC_HEADING_HIRAGANA = "もくじ"
  TOC_HEADINGS = [TOC_HEADING_JA, TOC_HEADING_EN, TOC_HEADING_HIRAGANA].freeze

  def toc_heading
    case current
    when "en" then TOC_HEADING_EN
    when "hiragana" then TOC_HEADING_HIRAGANA
    else TOC_HEADING_JA
    end
  end

  def toc_heading?(text)
    TOC_HEADINGS.include?(text.to_s.gsub(/[#\s　]/, ""))
  end

  def rewrite_structure_headings(body, language: current)
    text = body.to_s
    lang = Column.normalize_language(language)

    case lang
    when "en"
      text.sub(/^##[[:space:]]*目次[[:space:]]*$/, "## #{TOC_HEADING_EN}")
          .gsub(/^##[[:space:]]*もくじ[[:space:]]*$/, "## #{TOC_HEADING_EN}")
          .gsub(/^##[[:space:]]*まとめ[[:space:]]*$/, "## Conclusion")
    when "hiragana"
      normalize_hiragana_markdown(text)
        .sub(/^##[[:space:]]*目次[[:space:]]*$/, "## #{TOC_HEADING_HIRAGANA}")
        .gsub(/^##[[:space:]]*Contents[[:space:]]*$/, "## #{TOC_HEADING_HIRAGANA}")
        .gsub(/^##[[:space:]]*Conclusion[[:space:]]*$/, "## まとめ")
    else
      text
    end
  end

  ATX_HEADING = /\#{2,3}[[:space:]]+/

  def normalize_hiragana_markdown(text)
    text.to_s
      .tr("．", "。")
      .tr("，", "、")
      .gsub(/[ \t]+\n/, "\n")
      .gsub(/([^\n])(#{ATX_HEADING})/, "\\1\n\n\\2")
      .gsub(/(#{ATX_HEADING}[^\n]+)(?=#{ATX_HEADING})/, "\\1\n\n")
      .gsub(/([^\n])\n(#{ATX_HEADING})/, "\\1\n\n\\2")
      .gsub(/(#{ATX_HEADING}[^\n]+)\n(?!\n)/, "\\1\n\n")
  end

  def prepare_user_prompt(prompt)
    text = prompt.to_s
    return text if hiragana? || language_locked_prompt?(text)

    pack = GptPromptPack.for(current)
    return text unless pack.exist?("wrap")

    pack.render("wrap", task: neutralize_task(text))
  end

  def language_locked_prompt?(prompt)
    prompt.to_s.start_with?("LANGUAGE:")
  end

  def neutralize_task(text)
    return neutralize_japanese_output_instructions(text) if english?

    text
  end

  KANJI_PATTERN = /[\u4e00-\u9fff]/

  def contains_kanji?(text)
    text.to_s.match?(KANJI_PATTERN)
  end

  def hiragana_kanji_violation?(text)
    hiragana? && contains_kanji?(text)
  end

  def kanji_rewrite_user_prompt(_text)
    raise ArgumentError, "ひらがなプロンプトはありません"
  end

  def strip_code_fences(content)
    content.to_s.sub(/\A```[a-z]*\n/i, "").sub(/```\z/m, "")
  end

  def rewrite_until_hiragana(content)
    text = strip_code_fences(content).strip
    raise "empty content" if text.blank?
    unless hiragana_kanji_violation?(text)
      return hiragana? ? normalize_hiragana_markdown(text) : text
    end
    return normalize_hiragana_markdown(text) unless block_given?

    3.times do
      rewritten = strip_code_fences(yield(kanji_rewrite_user_prompt(text))).strip
      next if rewritten.blank?

      text = rewritten
      break unless hiragana_kanji_violation?(text)
    end
    raise "kanji remaining" if hiragana_kanji_violation?(text)

    normalize_hiragana_markdown(text)
  end

  def finalize_text_section(content, &block)
    rewrite_until_hiragana(content, &block)
  end

  def ensure_hiragana_document(body)
    text = normalize_hiragana_markdown(body.to_s)
    if hiragana_kanji_violation?(text) && block_given?
      text = text.split(/(?=^\#\# )/m).map do |chunk|
        next chunk if chunk.strip.blank?

        rewrite_until_hiragana(chunk) { |prompt| yield(prompt) }
      end.join
    end
    normalize_hiragana_markdown(text)
  end

  HIRAGANA_ARTICLE_MAX_CHARS = 1800

  def compact_hiragana_user_prompt(_text)
    raise ArgumentError, "ひらがなプロンプトはありません"
  end

  def compact_hiragana_article(body)
    text = normalize_hiragana_markdown(body.to_s)
    return text unless hiragana?
    return text unless block_given?
    return text if text.blank?

    3.times do
      rewritten = strip_code_fences(yield(compact_hiragana_user_prompt(text))).strip
      next if rewritten.blank?

      text = normalize_hiragana_markdown(rewritten)
      break unless contains_kanji?(text) || text.length > HIRAGANA_ARTICLE_MAX_CHARS
    end
    raise "kanji remaining" if contains_kanji?(text)

    text
  end

  def finalize_hiragana_article(body, &block)
    text = normalize_hiragana_markdown(body.to_s)
    return text unless hiragana?
    return text if text.present? && !contains_kanji?(text) && text.length <= HIRAGANA_ARTICLE_MAX_CHARS

    compact_hiragana_article(text, &block)
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
      .gsub("## もくじ", "## Contents")
      .gsub("## まとめ", "## Conclusion")
      .gsub(/(^|\n)(\s*[-*]\s*)日本語(\s*)(?=\n|$)/, '\1\2English\3')
  end

  def resolve_system_prompt(japanese_system, json_mode:)
    # 日本語はジェネレータごとの system（Qiita / Zenn など）を維持する。
    return japanese_system if current == "ja" || hiragana?

    pack = GptPromptPack.for(current)
    return japanese_system unless pack.exist?("system")

    pack.system_prompt(json_mode: json_mode)
  end

  def resolve_title_system_prompt(japanese_system)
    return japanese_system if hiragana?

    pack = GptPromptPack.for(current)
    return japanese_system unless pack.exist?("title_system")

    pack.render("title_system").to_s.strip
  end

  def min_length(japanese_min)
    return (japanese_min.to_i * 1.8).to_i if english?
    return (japanese_min.to_i * 0.35).to_i if hiragana?

    japanese_min
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

  FAILURE_BODY_PATTERNS = [
    /生成失敗/,
    /生成に失敗/,
    /本文の生成に失敗/,
    /本文生成に失敗/,
    /生成エラーにより/,
    /generation failed/i,
    /\A❌[[:space:]]*失敗:/
  ].freeze

  def failed_output?(text)
    value = text.to_s
    return true if value.strip.empty?

    FAILURE_BODY_PATTERNS.any? { |pattern| value.match?(pattern) }
  end

  # gpt-5 / o 系は temperature などサンプリングパラメータを拒否する。
  def sampling_parameters_supported?(model)
    name = model.to_s.downcase
    return true if name.include?("chat")
    return false if name.match?(/\A(o1|o3|o4|gpt-5)/)

    true
  end

  def chat_completions_payload(model:, messages:, json_mode: false, temperature: nil)
    payload = { model: model, messages: messages }
    payload[:response_format] = { type: "json_object" } if json_mode
    if temperature && sampling_parameters_supported?(model)
      payload[:temperature] = temperature
    end
    payload
  end

  def section_failure_message(name)
    case current
    when "en"
      "(Body generation failed for #{name}. Please regenerate.)"
    when "hiragana"
      "（#{name}の本文生成に失敗しました。もういちどつくってください。）"
    else
      "（#{name}の本文生成に失敗しました。再生成してください。）"
    end
  end
end
