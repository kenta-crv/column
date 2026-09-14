require "net/http"
require "json"
require "openssl"

class GptPillarGenerator
  class GenerationCancelledError < StandardError; end

  MODEL_NAME = "gpt-5.4-nano"
  GPT_API_URL = "https://api.openai.com/v1/chat/completions"

  # ==========================================================
  # メイン生成ロジック
  # ==========================================================
  def self.generate_full_from_existing_column!(column)
    raise "タイトルが空です" if column.title.blank?
    ensure_not_cancelled!(column)

    client = column.client
    target_category = detect_category(column)
    current_genre   = column.genre.presence || GenreRegistry.from_ja(target_category) || "other"

    puts "▶ 統合生成開始: #{column.title} (判定: #{target_category}, genre: #{current_genre})"

    # ----------------------------------------------------------
    # Genre情報取得（保存済み中分類を優先）
    # ----------------------------------------------------------
    genre_data = GenreRegistry.genre_entry(current_genre, client: client) || {}
    sub_key    = GenreRegistry.resolve_sub_category_key(column, current_genre, client: client)
    sub_data   = sub_key.present? ? genre_data.dig(:sub_categories, sub_key.to_sym) : nil
    generation_locale = Column.english_language?(column.language) ? :en : :ja
    genre_data, sub_data = GenreRegistry.for_generation(genre_data, sub_data, locale: generation_locale)

    # ----------------------------------------------------------
    # EEATコンテキスト生成
    # ----------------------------------------------------------
    eeat_context = build_eeat_context(
      column,
      genre_data,
      sub_data
    )

    # ----------------------------------------------------------
    # Meta生成
    # ----------------------------------------------------------
    meta_data = nil

    3.times do |i|
      ensure_not_cancelled!(column)
      res = generate_meta_info(
        column,
        target_category,
        genre_data,
        sub_data,
        eeat_context
      )

      if res.present?
        meta_data = res
        break
      end

      puts "⚠️ Meta生成失敗 再試行中... (#{i + 1}/3) #{last_gpt_error}"
      sleep(2)
    end

    detail = last_gpt_error.presence || "原因不明（API応答なし / JSON解析失敗）"
    raise "Meta情報の生成に失敗しました (#{detail})" if meta_data.nil?

    clean_code = Column.sanitize_seo_code(meta_data["code"])

    # ----------------------------------------------------------
    # 構成生成
    # ----------------------------------------------------------
    structure_data = nil

    3.times do |i|
      ensure_not_cancelled!(column)
      res = generate_structure(
        column,
        target_category,
        genre_data,
        sub_data,
        eeat_context
      )

      if res.present? && res["structure"].present?
        structure_data = res
        break
      end

      puts "⚠️ 構成生成失敗 再試行中... (#{i + 1}/3)"
      sleep(2)
    end

    raise "記事構成の生成に失敗しました" if structure_data.nil?

    # ----------------------------------------------------------
    # 中間保存
    # ----------------------------------------------------------
    column.update!(
      description: meta_data["description"],
      keyword: meta_data["keyword"],
      choice: target_category,
      genre: current_genre,
      status: "creating",
      article_type: "pillar",
      **column.seo_code_assignment(clean_code)
    )

    # ----------------------------------------------------------
    # 本文生成
    # ----------------------------------------------------------
    body_content = ""
    covered_points = [] # ← 既出セクションの要旨を蓄積し、重複を防ぐ

    # 導入文
    ensure_not_cancelled!(column)
    body_content += call_text_section(
      introduction_prompt(
        column,
        target_category,
        genre_data,
        sub_data,
        eeat_context
      )
    )

    body_content += "\n\n"

    body_content += "## #{GptGenerationLocale.toc_heading}\n\n"

    structure_data["structure"].each do |section|
      ensure_not_cancelled!(column)
      body_content += "- #{section["h2_title"]}\n"
    end

    body_content += "\n"

    # H2セクション
    structure_data["structure"].each do |section|
      ensure_not_cancelled!(column)
      h2_title = section["h2_title"]

      body_content += "## #{h2_title}\n\n"

      section_body = call_text_section(
        h2_content_prompt(
          column,
          target_category,
          section,
          genre_data,
          sub_data,
          eeat_context,
          covered_points
        )
      )

      section_body.gsub!(/\A\s*#+\s+#{Regexp.escape(h2_title)}\s*\n+/i, "")
      section_body.gsub!(/\A\s*#{Regexp.escape(h2_title)}\s*\n+/i, "")

      # 表・チェックリストの構文バリデーション（列崩れ対策）
      section_body = sanitize_markdown_table(section_body)

      body_content += section_body
      body_content += "\n\n"

      # このセクションの要旨を記録し、次のセクション生成時に「既出」として渡す
      covered_points << {
        title: h2_title,
        gist: extract_gist(section_body)
      }

      sleep(1.2)
    end

    # まとめ
    ensure_not_cancelled!(column)
    body_content += call_text_section(
      conclusion_prompt(
        column,
        target_category,
        genre_data,
        sub_data,
        eeat_context,
        covered_points
      )
    )

    body_content += "\n\n{::options auto_ids=\"false\" /}"

    body_content = GptGenerationLocale.finalize_hiragana_article(body_content) do |retry_prompt|
      retry_response = call_gpt_api(retry_prompt, json_mode: false)
      retry_response&.dig("choices", 0, "message", "content")
    end

    # ----------------------------------------------------------
    # 保存
    # ----------------------------------------------------------
    ensure_not_cancelled!(column)
    column.update!(
      body: body_content,
      status: "completed"
    )

    puts "✅ 生成完了: #{clean_code}"

    true
  end

  def self.ensure_not_cancelled!(column)
    return unless GenerateColumnBodyJob.cancelled?(column.id)

    raise GenerationCancelledError, "記事生成がユーザー操作で停止されました"
  end

  private

  # ==========================================================
  # カテゴリ判定
  # ==========================================================
  def self.detect_category(column)
    search_text = [
      column.title,
      column.keyword,
      column.genre,
      column.choice
    ].join(" ")

    GenreRegistry::GENRES.each do |_, data|
      next unless data[:keywords]

      if data[:keywords].any? { |w| search_text.include?(w) }
        return data[:ja]
      end
    end

    "その他"
  end

  # ==========================================================
  # EEATコンテキスト
  # ==========================================================
  def self.build_eeat_context(column, genre_data, sub_data)
    contexts = []

    contexts << "記事ジャンル: #{genre_data[:ja]}" if genre_data[:ja].present?

    if genre_data[:keywords].present?
      contexts << "関連キーワード: #{genre_data[:keywords].join('、')}"
    end

    if sub_data.present?
      contexts << "対象読者: #{sub_data[:target]}" if sub_data[:target].present?
      contexts << "業界説明: #{sub_data[:description]}" if sub_data[:description].present?
      contexts << "業界特徴: #{sub_data[:features].join('、')}" if sub_data[:features].present?
      contexts << "業界課題: #{sub_data[:industry_weakness]}" if sub_data[:industry_weakness].present?
    end

    contexts << <<~TEXT
      以下を重視して執筆すること:
      - 実務レベルで説明する
      - 一次情報ベースで語る
      - 比較サイト風にしない
      - 誇張表現を使わない
      - 業界構造を解説する
      - 現場視点を含める
      - 初心者向けではなく実務寄りにする
      - SEO目的だけの記事にしない
      - 読者が実際に調査している内容を深掘りする
      - 汎用的な業界記事として成立させる
    TEXT

    contexts.join("\n")
  end

  # ==========================================================
  # SEOメタ生成
  # ==========================================================
  def self.generate_meta_info(column, category, genre_data, sub_data, eeat_context)
    prompt = meta_prompt(column, category, genre_data, sub_data, eeat_context)

    res = call_gpt_api(prompt, json_mode: true)

    return nil unless res

    content = res.dig("choices", 0, "message", "content")
    if content.blank?
      remember_gpt_error!("empty content in choices[0].message.content")
      return nil
    end

    JSON.parse(content)
  rescue => e
    remember_gpt_error!("parse error: #{e.message}")
    puts "❌ generate_meta_info parse error: #{e.message}"
    nil
  end

  # ==========================================================
  # 構成生成（H2ごとに表・チェックリストの適性フラグを付与）
  # ==========================================================
  def self.generate_structure(column, category, genre_data, sub_data, eeat_context)
    child_columns = Column.where(
      parent_id: column.id,
      article_type: "child"
    )

    child_titles = child_columns.map(&:title)
    prompt = structure_prompt(column, category, genre_data, sub_data, eeat_context, child_titles)

    res = call_gpt_api(prompt, json_mode: true)

    return nil unless res

    JSON.parse(
      res.dig("choices", 0, "message", "content")
    )
  rescue => e
    puts "❌ generate_structure parse error: #{e.message}"
    nil
  end

  # ==========================================================
  # 本文生成
  # ==========================================================
  def self.call_text_section(prompt)
    max_retries = 3
    retries = 0

    begin
      response = call_gpt_api(prompt, json_mode: false)

      content = response&.dig("choices", 0, "message", "content")

      raise "empty content" if content.blank?

      content = GptGenerationLocale.finalize_text_section(content) do |retry_prompt|
        retry_response = call_gpt_api(retry_prompt, json_mode: false)
        retry_response&.dig("choices", 0, "message", "content")
      end

      content
    rescue => e
      retries += 1

      if retries < max_retries
        puts "⚠️ 本文生成失敗 再試行中... (#{retries}/#{max_retries}) #{e.message}"
        sleep(2)
        retry
      end

      "（生成エラーにより本文生成に失敗しました）"
    end
  end

  # ==========================================================
  # GPT API
  # ==========================================================
  def self.last_gpt_error
    Thread.current[:gpt_pillar_last_error]
  end

  def self.remember_gpt_error!(message)
    Thread.current[:gpt_pillar_last_error] = redact_secrets(message.to_s)
  end

  def self.redact_secrets(text)
    text
      .gsub(/sk-[a-zA-Z0-9_\-]+/, "[REDACTED_KEY]")
      .gsub(/Bearer\s+[A-Za-z0-9\-._]+/i, "Bearer [REDACTED_KEY]")
  end

  def self.summarize_openai_error(code, body)
    parsed = JSON.parse(body) rescue nil
    msg =
      if parsed.is_a?(Hash)
        parsed.dig("error", "message").presence ||
          parsed.dig("error", "code").presence ||
          body.to_s
      else
        body.to_s
      end

    remember_gpt_error!("HTTP #{code}: #{msg.to_s.truncate(400)}")
  end

  def self.call_gpt_api(prompt, json_mode: false)
    prompt = GptGenerationLocale.prepare_user_prompt(prompt)
    uri = URI(GPT_API_URL)

    req = Net::HTTP::Post.new(uri)

    req["Content-Type"] = "application/json"
    req["Authorization"] = "Bearer #{ENV["GPT_API_KEY"]}"

    system_content = GptPromptPack.for("ja").system_prompt(json_mode: json_mode)
    system_content = GptGenerationLocale.resolve_system_prompt(system_content, json_mode: json_mode)

    payload = GptGenerationLocale.chat_completions_payload(
      model: MODEL_NAME,
      messages: [
        {
          role: "system",
          content: system_content
        },
        {
          role: "user",
          content: prompt
        }
      ],
      json_mode: json_mode,
      temperature: 0.45
    )

    req.body = payload.to_json

    begin
      res = Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: true,
        read_timeout: 120
      ) do |http|
        http.request(req)
      end

      if res.is_a?(Net::HTTPSuccess)
        Thread.current[:gpt_pillar_last_error] = nil
        JSON.parse(res.body)
      else
        summarize_openai_error(res.code, res.body)
        puts "❌ OpenAI Error: #{res.code} #{redact_secrets(res.body.to_s)}"
        nil
      end
    rescue => e
      remember_gpt_error!("API Exception: #{e.message}")
      puts "❌ API Exception: #{e.message}"
      nil
    end
  end

  def self.pillar_prompt_locals(column, category, genre_data, sub_data, eeat_context, extra = {})
    {
      title: column.title,
      category: category,
      extra_prompt: column.prompt,
      industry_context: build_industry_context(genre_data, sub_data),
      eeat_context: eeat_context
    }.merge(extra)
  end
  private_class_method :pillar_prompt_locals

  def self.meta_prompt(column, category, genre_data, sub_data, eeat_context)
    GptPromptPack.for("ja").render("meta", **pillar_prompt_locals(column, category, genre_data, sub_data, eeat_context))
  end

  def self.structure_prompt(column, category, genre_data, sub_data, eeat_context, child_titles = [])
    GptPromptPack.for("ja").render(
      "structure",
      **pillar_prompt_locals(
        column,
        category,
        genre_data,
        sub_data,
        eeat_context,
        child_titles_text: Array(child_titles).join("\n")
      )
    )
  end

  # ==========================================================
  # 導入文
  # ==========================================================
  def self.introduction_prompt(column, category, genre_data, sub_data, eeat_context)
    GptPromptPack.for("ja").render("introduction", **pillar_prompt_locals(column, category, genre_data, sub_data, eeat_context))
  end

  # ==========================================================
  # H2本文（has_table対応）
  # ==========================================================
  def self.h2_content_prompt(column, category, section, genre_data, sub_data, eeat_context, covered_points = [])
    GptPromptPack.for("ja").render(
      "h2",
      **pillar_prompt_locals(
        column,
        category,
        genre_data,
        sub_data,
        eeat_context,
        h2_title: section["h2_title"],
        covered_points_block: build_covered_points_block(covered_points),
        table_instruction: build_table_instruction(section)
      )
    )
  end

  # ==========================================================
  # 表・チェックリスト生成指示ブロック
  # ==========================================================
  def self.build_table_instruction(section)
    if section["has_table"]
      <<~TEXT
        【表・チェックリストの挿入(必須・どちらか1つを選ぶ)】
        この見出しの内容に応じて、以下のどちらかを1つだけ選んで本文中の適切な位置に挿入してください。両方入れない。

        ■ 表(Markdownテーブル)を選ぶ基準:
          - 複数の項目を「軸」で比較・分類する内容(例: 判断基準の一覧、選択肢ごとの特徴、条件と目安の対応表)
          - `| 項目 | 内容 |` のようなパイプ区切りのMarkdownテーブル形式を使用
          - ヘッダー行の直下に `|---|---|` の区切り行を必ず入れる
          - 各行の列数(パイプの数)は必ず揃える

        ■ チェックリストを選ぶ基準:
          - 「確認すべき項目」「作業前に揃えるべき条件」「実施すべき手順」など、Yes/No的に確認・実施できる内容
          - この基準に該当する場合は、通常の箇条書き `- 項目` ではなく、必ず `- [ ] 項目` の形式を使用する

        - 表・チェックリストは3〜6行程度に収め、情報を詰め込みすぎない
        - 表やチェックリストだけで終わらせず、その前後に必ず文章での解説を入れる
      TEXT
    else
      <<~TEXT
        【表・チェックリストについて】
        - この見出しでは表やチェックリストを無理に挿入しない。通常の文章のみで解説する
      TEXT
    end
  end

  # ==========================================================
  # まとめ
  # ==========================================================
  def self.conclusion_prompt(column, category, genre_data, sub_data, eeat_context, covered_points = [])
    GptPromptPack.for("ja").render(
      "conclusion",
      **pillar_prompt_locals(
        column,
        category,
        genre_data,
        sub_data,
        eeat_context,
        covered_points_block: build_covered_points_block(covered_points)
      )
    )
  end

  # ==========================================================
  # 既出セクション要旨ブロック生成
  # ==========================================================
  def self.build_covered_points_block(covered_points)
    return "" if covered_points.blank?

    lines = covered_points.map do |cp|
      "- #{cp[:title]}: #{cp[:gist]}"
    end

    <<~TEXT
      【既出セクションの要旨（重複禁止）】
      #{lines.join("\n")}
    TEXT
  end

  # ==========================================================
  # セクション要旨の抽出（次セクションへの重複防止用・API呼び出しなし）
  # 「セクション末尾の書き方」ルールにより、末尾に具体的な結論が来る前提のため、
  # 末尾1〜2文を要旨として採用する
  # ==========================================================
  def self.extract_gist(section_body)
    GptGenerationLocale.extract_gist(section_body)
  end

  # ==========================================================
  # Markdown表の簡易バリデーション
  # 列数が揃っていない、区切り行がないなど崩れた表は、事故を避けるため
  # テーブル記法を通常の箇条書き風テキストに変換して救済する
  # ==========================================================
  def self.sanitize_markdown_table(text)
    return text if text.blank?

    lines = text.split("\n")
    result = []
    i = 0

    while i < lines.length
      line = lines[i]

      if table_row?(line)
        table_block = []
        while i < lines.length && (table_row?(lines[i]) || separator_row?(lines[i]))
          table_block << lines[i]
          i += 1
        end

        if valid_table?(table_block)
          result.concat(table_block)
        else
          puts "⚠️ 崩れたMarkdown表を検出したため、テキスト形式に変換しました"
          table_block.each do |row|
            next if separator_row?(row)
            cells = row.split("|").map(&:strip).reject(&:blank?)
            result << "- #{cells.join(' / ')}" if cells.present?
          end
        end
      else
        result << line
        i += 1
      end
    end

    result.join("\n")
  end

  def self.table_row?(line)
    line.strip.start_with?("|") && line.strip.end_with?("|")
  end

  def self.separator_row?(line)
    line.strip =~ /\A\|?[\s:\-|]+\|?\z/ && line.include?("-")
  end

  def self.valid_table?(table_block)
    rows = table_block.reject { |r| separator_row?(r) }
    return false if rows.length < 2

    col_counts = rows.map { |r| r.split("|").length }
    col_counts.uniq.length == 1 && table_block.any? { |r| separator_row?(r) }
  end

  # ==========================================================
  # 業界コンテキスト生成
  # ==========================================================
  def self.build_industry_context(genre_data, sub_data)
    texts = []

    if genre_data.present?
      texts << "業界: #{genre_data[:ja]}" if genre_data[:ja].present?

      if genre_data[:keywords].present?
        texts << "業界キーワード: #{genre_data[:keywords].join('、')}"
      end
    end

    if sub_data.present?
      texts << "対象: #{sub_data[:target]}" if sub_data[:target].present?
      texts << "業界説明: #{sub_data[:description]}" if sub_data[:description].present?

      if sub_data[:features].present?
        texts << "業界特徴: #{sub_data[:features].join('、')}"
      end

      if sub_data[:industry_weakness].present?
        texts << "業界課題: #{sub_data[:industry_weakness]}"
      end
    end

    texts.join("\n")
  end
end