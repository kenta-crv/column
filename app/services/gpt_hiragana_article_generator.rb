# frozen_string_literal: true

# ひらがな記事は通常の日本語ピラー生成を使わない。
# 長い日本語プロンプトをラップすると漢字と冗長文が残るため、専用の一括生成にする。
class GptHiraganaArticleGenerator
  MAX_ATTEMPTS = 3

  def self.generate_full_from_existing_column!(column)
    raise "タイトルが空です" if column.title.blank?
    GptPillarGenerator.ensure_not_cancelled!(column)

    payload = nil
    last_error = nil

    MAX_ATTEMPTS.times do |i|
      GptPillarGenerator.ensure_not_cancelled!(column)
      payload = request_article_json(column)
      payload = strip_kanji_from_payload(payload)
      last_error = validate_payload(payload)
      break if last_error.nil?

      Rails.logger.warn("[GptHiraganaArticleGenerator] retry #{i + 1}/#{MAX_ATTEMPTS} column_id=#{column.id} #{last_error}")
      payload = nil
      sleep(1)
    end

    raise ColumnBodyGenerator::EmptyOutputError, "ひらがな本文の生成に失敗しました（#{last_error}）" if payload.nil?

    body = GptGenerationLocale.normalize_hiragana_markdown(payload["body"].to_s)
    attrs = {
      body: body,
      description: payload["description"].to_s.strip,
      keyword: payload["keyword"].to_s.strip,
      status: "completed"
    }
    if column.code.blank?
      attrs.merge!(column.seo_code_assignment(Column.sanitize_seo_code(payload["code"])))
    end
    column.update!(attrs)
    true
  end

  def self.build_article_prompt(column)
    GptPromptPack.for("hiragana").render(
      "article",
      title: column.title,
      article_type: column.article_type,
      source_facts: source_facts_for(column),
      extra_prompt: column.prompt.presence || "なし"
    )
  end

  def self.source_facts_for(column)
    client = column.client
    genre = column.genre.presence || "other"
    genre_data = GenreRegistry.genre_entry(genre, client: client) || {}
    sub_key = GenreRegistry.resolve_sub_category_key(column, genre, client: client)
    sub_data = sub_key.present? ? genre_data.dig(:sub_categories, sub_key.to_sym) : nil

    [
      "ジャンル: #{genre}",
      ("中分類キー: #{sub_key}" if sub_key.present?),
      ("中分類: #{sub_data[:name]}" if sub_data.is_a?(Hash) && sub_data[:name].present?),
      column.keyword.presence,
      column.description.presence
    ].compact.join("\n").truncate(500)
  end
  private_class_method :source_facts_for

  def self.request_article_json(column)
    res = GptPillarGenerator.send(:call_gpt_api, build_article_prompt(column), json_mode: true)
    content = GptGenerationLocale.strip_code_fences(res&.dig("choices", 0, "message", "content")).strip
    return nil if content.blank?

    parsed = JSON.parse(content)
    parsed.is_a?(Hash) ? parsed : nil
  rescue JSON::ParserError
    nil
  end
  private_class_method :request_article_json

  def self.strip_kanji_from_payload(payload)
    return payload unless payload.is_a?(Hash)

    %w[description keyword body].each do |key|
      value = payload[key].to_s
      next if value.blank? || !GptGenerationLocale.contains_kanji?(value)

      payload[key] = GptGenerationLocale.rewrite_until_hiragana(value) do |prompt|
        res = GptPillarGenerator.send(:call_gpt_api, prompt, json_mode: false)
        res&.dig("choices", 0, "message", "content")
      end
    end
    payload
  rescue StandardError => e
    Rails.logger.warn("[GptHiraganaArticleGenerator] kanji rewrite failed: #{e.message}")
    payload
  end
  private_class_method :strip_kanji_from_payload

  def self.validate_payload(payload)
    return "empty json" unless payload.is_a?(Hash)

    body = GptGenerationLocale.normalize_hiragana_markdown(payload["body"].to_s)
    description = payload["description"].to_s
    keyword = payload["keyword"].to_s
    combined = "#{description}\n#{keyword}\n#{body}"

    return "empty body" if body.blank?
    return "kanji remaining" if GptGenerationLocale.contains_kanji?(combined)
    return "inline toc" if body.match?(/^##[[:space:]]*(もくじ|目次)[[:space:]]*$/)
    return "missing heading" unless body.scan(/^##[[:space:]]+/).size >= 4
    return "too long" if body.length > 2200
    return "too short" if body.length < 500

    nil
  end
  private_class_method :validate_payload
end
