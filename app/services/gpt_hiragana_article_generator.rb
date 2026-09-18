# frozen_string_literal: true

require "open3"

# ひらがな記事の生成方式:
#   1. 漢字を使った、ふつうの日本語でGPTに書かせる（語彙の捏造を防ぐ）
#   2. MeCabで文全体を解析し、漢字を含む表層だけを辞書の読みへ置き換える
#   3. 最後にproofreadパスで、融合・重複・活用ミスなどの自然さを最終チェックする
class GptHiraganaArticleGenerator
  MAX_ATTEMPTS = 5

  MIN_BODY_CHARS = 500
  MAX_BODY_CHARS = 2200
  MAX_SENTENCE_CHARS = 80
  MIN_SENTENCE_CHARS = 8
  COMMA_REQUIRED_OVER_CHARS = 32
  SECTION_OVERLAP_THRESHOLD = 0.55

  KANJI_RANGE = /\p{Han}/

  def self.generate_full_from_existing_column!(column)
    raise "タイトルが空です" if column.title.blank?
    GptPillarGenerator.ensure_not_cancelled!(column)

    payload = nil
    last_error = nil

    MAX_ATTEMPTS.times do |i|
      GptPillarGenerator.ensure_not_cancelled!(column)

      raw = request_article_json(column)
      if raw.nil?
        last_error = "empty generation"
        Rails.logger.warn(
          "[GptHiraganaArticleGenerator] retry #{i + 1}/#{MAX_ATTEMPTS} " \
          "column_id=#{column.id} #{last_error}"
        )
        sleep(1)
        next
      end

      body = convert_to_hiragana(raw["body"].to_s)
      body = normalize_body(body, column.title)

      payload = {
        "code" => raw["code"],
        "description" => convert_to_hiragana(raw["description"].to_s),
        "keyword" => raw["keyword"].to_s,
        "body" => body
      }

      payload = proofread_payload(payload, column)
      payload["body"] = convert_to_hiragana(payload["body"].to_s)
      payload["body"] = normalize_body(payload["body"], column.title)

      last_error = validate_payload(payload, column: column)
      break if last_error.nil?

      Rails.logger.warn(
        "[GptHiraganaArticleGenerator] retry #{i + 1}/#{MAX_ATTEMPTS} " \
        "column_id=#{column.id} #{last_error}"
      )
      payload = nil
      sleep(1)
    end

    if payload.nil?
      raise ColumnBodyGenerator::EmptyOutputError,
            "ひらがな本文の生成に失敗しました（#{last_error}）"
    end

    attrs = {
      body: payload["body"].to_s,
      description: payload["description"].to_s.strip,
      keyword: payload["keyword"].to_s.strip,
      status: "completed",
      generation_status: "completed"
    }
    if column.code.blank?
      attrs.merge!(column.seo_code_assignment(Column.sanitize_seo_code(payload["code"])))
    end
    column.update!(attrs)
    true
  end

  # ---------- 生成（漢字ありの、ふつうの日本語） ----------

  def self.build_article_prompt(column)
    GptPromptPack.for("hiragana").render(
      "article",
      title: column.title,
      article_type: column.article_type,
      source_facts: source_facts_for(column),
      extra_prompt: column.prompt.presence || "なし"
    )
  end
  private_class_method :build_article_prompt

  def self.source_facts_for(column)
    hints = []
    hints << column.title.presence
    hints << squeeze_keywords(column.keyword)
    hints << column.description.presence
    text = hints.compact.join("\n").truncate(500)
    text.presence || "なし"
  end
  private_class_method :source_facts_for

  def self.squeeze_keywords(keyword)
    keyword.to_s.gsub(/[[:space:]]+/, "、").presence
  end
  private_class_method :squeeze_keywords

  def self.request_article_json(column)
    call_json(build_article_prompt(column))
  end
  private_class_method :request_article_json

  def self.call_text(prompt)
    res = GptPillarGenerator.send(:call_gpt_api, prompt, json_mode: false)
    GptGenerationLocale.strip_code_fences(res&.dig("choices", 0, "message", "content")).to_s
  end
  private_class_method :call_text

  def self.call_json(prompt)
    res = GptPillarGenerator.send(:call_gpt_api, prompt, json_mode: true)
    content = GptGenerationLocale
              .strip_code_fences(res&.dig("choices", 0, "message", "content")).to_s.strip
    return nil if content.blank?

    parsed = JSON.parse(content)
    parsed.is_a?(Hash) ? parsed : nil
  rescue JSON::ParserError
    nil
  end
  private_class_method :call_json

  # ---------- 変換 ----------
  # 読みはGPTに作らせない。MeCabが文全体を解析し、漢字を含む表層だけを辞書読みへ置く。

  # 「ページ＋内」が一つの語に融合したときだけ直す。題材ごとの言い換えはしない。
  INNER_FUSION_REWRITES = {
    "ぺーじないで" => "ぺーじのなかで",
    "ページないで" => "ページのなかで",
    "ぺーじないの" => "ぺーじのなかの",
    "ページないの" => "ページのなかの"
  }.freeze

  def self.convert_to_hiragana(text)
    result = MecabReadingConverter.convert(text)
    INNER_FUSION_REWRITES.each { |bad, good| result = result.gsub(bad, good) }
    if result.match?(KANJI_RANGE)
      leftover = result.scan(KANJI_RANGE).uniq.join(",")
      Rails.logger.warn("[GptHiraganaArticleGenerator] kanji leftover: #{leftover}")
    end
    result
  end
  private_class_method :convert_to_hiragana

  # ---------- 機械的な整形（構造のみ。語の中身には触れない） ----------

  def self.normalize_body(body, title)
    body = strip_leading_h1(body)
    body = ensure_opening_lead(body, title)
    body = collapse_wakachigaki(body)
    body = fix_comma_splice(body)
    body = insert_commas_in_long_sentences(body)
    body = strip_heading_periods(body)
    body = strip_inline_toc(body)
    body = strip_duplicate_lead(body)
    body
  end
  private_class_method :normalize_body

  def self.strip_leading_h1(body)
    body.sub(/\A(?:#(?!#)[^\n]*(?:\n+|\z))+/, "")
  end
  private_class_method :strip_leading_h1

  def self.ensure_opening_lead(body, title)
    return body if title.blank?
    return body unless body.match?(/\A[[:space:]]*##/)

    lead = title.to_s.split(/[｜|]/).map { |part|
      part = part.strip.sub(/[。．]\z/, "")
      part.present? ? "#{part}。" : nil
    }.compact.join
    return body if lead.blank?

    "#{lead}\n\n#{body.lstrip}"
  end
  private_class_method :ensure_opening_lead

  def self.collapse_wakachigaki(body)
    body.gsub(
      /(?<=[\p{Hiragana}\p{Katakana}ー0-9])[ \t　]+(?=[\p{Hiragana}\p{Katakana}ー0-9])/,
      ""
    )
  end
  private_class_method :collapse_wakachigaki

  def self.fix_comma_splice(body)
    body.gsub(/(です|ます|ません|でした|ました|でしょう)、(?=[^\n）」』】]{2,})/) do
      "#{Regexp.last_match(1)}。"
    end
  end
  private_class_method :fix_comma_splice

  def self.insert_commas_in_long_sentences(body)
    body.split(/(?<=\n)/).map { |chunk|
      next chunk if chunk.match?(/\A\#{2,3}[[:space:]]/)

      chunk.gsub(/([^。\n]{#{COMMA_REQUIRED_OVER_CHARS + 1},}。)/) do |sentence|
        next sentence if sentence.include?("、")

        core = sentence.sub(/。\z/, "")
        inserted = core.sub(
          /\A(.{10,#{COMMA_REQUIRED_OVER_CHARS}}?(?:ので|から|ては|ても|には|では|を|が|は|に|で|て))/,
          "\\1、"
        )
        inserted = "#{core[0, core.length / 2]}、#{core[(core.length / 2)..]}" if inserted == core
        "#{inserted}。"
      end
    }.join
  end
  private_class_method :insert_commas_in_long_sentences

  def self.strip_heading_periods(body)
    body.gsub(/^(\#{2,3}[^\n]+?)[。．][[:space:]]*$/, '\1')
  end
  private_class_method :strip_heading_periods

  def self.strip_inline_toc(body)
    body.gsub(/^##[[:space:]]*(もくじ|目次)[[:space:]]*$\n(?:[[:space:]]*[-*][^\n]*\n)*/, "")
  end
  private_class_method :strip_inline_toc

  def self.strip_duplicate_lead(body)
    blocks = body.split(/\n{2,}/)
    return body if blocks.size < 2

    lead = blocks[0].to_s.strip
    return body if lead.blank? || lead.start_with?("#") || lead.length > 120

    following = blocks[1].to_s.scan(/[^。\n]+。/).first(2).join
    return body if following.blank?
    return body unless ngram_overlap(lead, following) >= 0.5

    blocks[1..].join("\n\n")
  end
  private_class_method :strip_duplicate_lead

  # ---------- 校正パス（文法・自然さの最終チェック） ----------

  def self.proofread_payload(payload, column)
    return payload unless payload.is_a?(Hash)

    body = payload["body"].to_s
    return payload if body.blank?

    facts = source_facts_for(column)
    pack = GptPromptPack.for("hiragana")

    result = call_json(pack.render("proofread", text: body, source_facts: facts))
    return payload if result.nil?

    issues = Array(result["issues"]).select { |h| h.is_a?(Hash) && h["quote"].present? }
    return payload if issues.empty?

    issues_text = issues.map.with_index(1) do |issue, idx|
      "#{idx}. 箇所: #{issue['quote']}\n   理由: #{issue['reason']}\n   直し: #{issue['suggestion']}"
    end.join("\n")

    fixed = call_text(pack.render("apply_fixes", text: body, issues_text: issues_text)).strip
    return payload if fixed.blank?
    return payload if fixed.length < (body.length * 0.6)

    payload["body"] = fixed
    payload
  rescue StandardError => e
    Rails.logger.warn("[GptHiraganaArticleGenerator] proofread failed: #{e.message}")
    payload
  end
  private_class_method :proofread_payload

  # ---------- 検証 ----------

  def self.validate_payload(payload, column: nil)
    return "empty json" unless payload.is_a?(Hash)

    body = payload["body"].to_s
    return "empty body" if body.blank?

    if body.match?(KANJI_RANGE)
      leftover = body.scan(KANJI_RANGE).uniq.join(",")
      return "kanji remaining #{leftover}"
    end
    banned = banned_reading(body)
    return "banned reading #{banned}" if banned
    return "title as h1" if body.match?(/\A#(?!#)/)
    return "inline toc" if body.match?(/^##[[:space:]]*(もくじ|目次)[[:space:]]*$/)
    return "missing heading" unless body.scan(/^##[[:space:]]+/).size >= 4
    return "keyword missing from intro" if keyword_missing_from_intro?(body, column)
    return "title number missing" if title_number_missing?(body, column)
    return "heading period" if body.match?(/^##[^\n]+[。．][[:space:]]*$/)
    return "heading inline body" if body.match?(/^##[[:space:]]+[^\n]*。[^\n]+$/)
    return "too long" if body.length > MAX_BODY_CHARS
    return "too short" if body.length < MIN_BODY_CHARS
    return "latin leak" if body.match?(/[A-Za-z]{3,}/)

    prose = body.lines.reject { |line| line.match?(/\A#+[[:space:]]/) }.join
    return "wakachigaki" if prose.scan(/[\p{Hiragana}\p{Katakana}][[:space:]]+[\p{Hiragana}\p{Katakana}]/).size >= 3

    sentences = prose.scan(/[^。\n]+。/).map { |s| s.delete("\n").strip }
    return "no sentence" if sentences.empty?

    return "comma splice" if prose.match?(/(です|ます|ません|でした|ました|でしょう)、/)
    return "quiz sentence" if prose.include?("ですか")

    return "sentence too long" if sentences.any? { |s| s.length > MAX_SENTENCE_CHARS }
    short = sentences.count { |s| s.length <= MIN_SENTENCE_CHARS }
    return "staccato" if short >= [(sentences.size * 0.3).ceil, 3].max

    missing_comma = sentences.count do |s|
      s.length > COMMA_REQUIRED_OVER_CHARS && !s.include?("、")
    end
    return "missing commas in long sentences" if missing_comma >= 2

    return "monotonous endings" if monotonous_endings?(sentences)

    dup = duplicated_section(body)
    return "duplicated section #{dup}" if dup

    ungrounded = ungrounded_numbers(body, column)
    return "ungrounded number #{ungrounded.join(',')}" if ungrounded.any?

    weakened = weakened_limit(sentences)
    return "number weakened as めやす: #{weakened}" if weakened

    nil
  end
  private_class_method :validate_payload

  BANNED_READINGS = %w[
    にっぽん
    にゅうこくかんりきょく
    にゅうこくかんりちょう
    ぺーじないで
    ページないで
    ページないの
    ぺーじないの
  ].freeze

  def self.banned_reading(body)
    BANNED_READINGS.find { |word| body.include?(word) }
  end
  private_class_method :banned_reading

  def self.title_number_missing?(body, column)
    return false if column.nil?

    column.title.to_s.scan(/\d+/).any? do |num|
      num.length >= 2 && !body.include?(num)
    end
  end
  private_class_method :title_number_missing?

  def self.keyword_missing_from_intro?(body, column)
    return false if column.nil?

    lead = body.split(/^##[[:space:]]+/, 2).first.to_s
    tokens = intro_keyword_tokens(column)
    return false if tokens.empty?

    tokens.none? { |token| lead.include?(token) }
  end
  private_class_method :keyword_missing_from_intro?

  def self.intro_keyword_tokens(column)
    raw = [column.title, column.keyword].compact.join(" ")
    raw.split(/[[:space:]｜|、,]+/).map(&:strip).reject { |token|
      token.length < 3 || %w[まとめ について とは].include?(token)
    }.flat_map { |token|
      converted = MecabReadingConverter.convert(token)
      [token, converted].map(&:strip).reject(&:blank?)
    }.uniq
  end
  private_class_method :intro_keyword_tokens

  def self.monotonous_endings?(sentences)
    run = 1
    sentences.each_cons(2) do |a, b|
      run = (tail(a) == tail(b) ? run + 1 : 1)
      return true if run >= 4
    end
    false
  end
  private_class_method :monotonous_endings?

  def self.tail(str)
    str.to_s.sub(/。\z/, "")[-3..] || str.to_s
  end
  private_class_method :tail

  def self.duplicated_section(body)
    sections = body.split(/^##[[:space:]]+/).drop(1)
    return nil if sections.size < 2

    sections.combination(2).each do |a, b|
      label_a = a.lines.first.to_s.strip
      label_b = b.lines.first.to_s.strip
      next if label_a.blank? || label_b.blank?
      next if [label_a, label_b].any? { |label| label == "まとめ" }

      return "#{label_a}/#{label_b}" if ngram_overlap(a, b) >= SECTION_OVERLAP_THRESHOLD
    end
    nil
  end
  private_class_method :duplicated_section

  def self.ungrounded_numbers(body, column)
    return [] if column.nil?

    reference = [
      column.title, column.keyword, column.description, column.prompt
    ].compact.join(" ")

    body.scan(/\d+/).uniq.reject do |num|
      num.length < 2 || reference.include?(num)
    end
  end
  private_class_method :ungrounded_numbers

  def self.weakened_limit(sentences)
    sentences.find do |s|
      s.match?(/\d+[^\d。、]{0,6}(まで|いじょう|いか)/) && s.include?("めやす")
    end
  end
  private_class_method :weakened_limit

  def self.ngram_overlap(left, right, n = 2)
    a = normalize_for_compare(left).chars.each_cons(n).map(&:join).uniq
    b = normalize_for_compare(right).chars.each_cons(n).map(&:join).uniq
    return 0.0 if a.empty? || b.empty?

    (a & b).size.to_f / [a.size, b.size].min
  end
  private_class_method :ngram_overlap

  def self.normalize_for_compare(text)
    text.to_s.gsub(/[[:space:]#、。]/, "")
  end
  private_class_method :normalize_for_compare

  # 漢字を含む表層だけをIPADICの読み（ひらがな）に置換する。
  # 助詞・カタカナ・記号の表層は変えない（「は」を「わ」にしない）。
  class MecabReadingConverter
    class Unavailable < StandardError; end

    OVERRIDES = {
      "出入国在留管理庁" => "しゅつにゅうこくざいりゅうかんりちょう",
      "資格外活動" => "しかくがいかつどう",
      "技術・人文知識・国際業務" => "ぎじゅつ・じんぶんちしき・こくさいぎょうむ",
      "日本人の配偶者等" => "にほんじんのはいぐうしゃとう",
      "永住者の配偶者等" => "えいじゅうしゃのはいぐうしゃとう",
      "在留カード" => "ざいりゅうカード",
      "在留資格" => "ざいりゅうしかく",
      "在留期間" => "ざいりゅうきかん",
      "特定技能" => "とくていぎのう",
      "技能実習" => "ぎのうじっしゅう",
      "特定活動" => "とくていかつどう",
      "育成就労" => "いくせいしゅうろう",
      "経営・管理" => "けいえい・かんり",
      "永住者" => "えいじゅうしゃ",
      "定住者" => "ていじゅうしゃ",
      "指定書" => "していしょ",
      "入国管理局" => "にゅうかん",
      "入国管理庁" => "にゅうかん",
      "入管" => "にゅうかん",
      "日本人" => "にほんじん",
      "日本" => "にほん"
    }.freeze

    DIC_CANDIDATES = [
      ENV["MECAB_DICDIR"],
      "/opt/homebrew/lib/mecab/dic/ipadic",
      "/usr/lib64/mecab/dic/ipadic",
      "/usr/lib/x86_64-linux-gnu/mecab/dic/ipadic-utf8",
      "/usr/lib/mecab/dic/ipadic-utf8",
      "/var/lib/mecab/dic/ipadic-utf8"
    ].freeze

    BIN_CANDIDATES = [
      ENV["MECAB_PATH"],
      "/opt/homebrew/bin/mecab",
      "/usr/bin/mecab"
    ].freeze

    def self.convert(text)
      new.convert(text)
    end

    def self.available?
      converter = new
      converter.send(:binary)
      converter.send(:dicdir)
      true
    rescue Unavailable
      false
    end

    def convert(text)
      return text if text.blank?

      prepared = apply_overrides(text.to_s)
      prepared.split(/(\n)/, -1).map { |part|
        part == "\n" || part.empty? ? part : convert_line(part)
      }.join
    end

    private

    def apply_overrides(text)
      OVERRIDES.sort_by { |kanji, _| -kanji.length }.reduce(text) do |acc, (kanji, reading)|
        acc.gsub(kanji, reading)
      end
    end

    SPACE_MARKERS = {
      " " => "\uE000",
      "\t" => "\uE001",
      "　" => "\uE002"
    }.freeze

    def convert_line(line)
      protected = line.dup
      SPACE_MARKERS.each { |char, marker| protected = protected.gsub(char, marker) }

      stdout, status = Open3.capture2(*mecab_command, stdin_data: "#{protected}\n")
      unless status.success?
        raise Unavailable, "MeCabの実行に失敗しました（exit #{status.exitstatus}）"
      end

      rendered = stdout.each_line.map { |row| render_token(row) }.join
      SPACE_MARKERS.each { |char, marker| rendered = rendered.gsub(marker, char) }
      rendered
    end

    def render_token(row)
      row = row.to_s.sub(/\n\z/, "")
      return "" if row.empty? || row == "EOS"

      surface, features = row.split("\t", 2)
      return surface.to_s if features.blank?
      return surface unless surface.match?(/\p{Han}/)

      cols = features.split(",")
      reading = cols[7].to_s
      return surface if reading.blank? || reading == "*"

      kata_to_hira(reading)
    end

    def kata_to_hira(str)
      str.to_s.gsub("ヴ", "ゔ").tr("ァ-ン", "ぁ-ん")
    end

    def mecab_command
      [binary, "-d", dicdir]
    end

    def binary
      @binary ||= begin
        path = BIN_CANDIDATES.compact.find { |candidate| File.executable?(candidate) }
        path ||= `command -v mecab 2>/dev/null`.to_s.strip.presence
        raise Unavailable, "MeCabが見つかりません。mecab をインストールしてください。" if path.blank?

        path
      end
    end

    def dicdir
      @dicdir ||= begin
        path = DIC_CANDIDATES.compact.find { |candidate| File.directory?(candidate) }
        raise Unavailable, "MeCab辞書が見つかりません。mecab-ipadic-utf8 をインストールしてください。" if path.blank?

        path
      end
    end
  end
end