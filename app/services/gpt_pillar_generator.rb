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

    clean_code = meta_data["code"].to_s.downcase
                  .gsub(/[^a-z0-9\s\-]/, "")
                  .strip
                  .gsub(/[\s_]+/, "-")
                  .gsub(/-+/, "-")
                  .gsub(/\A-|-\z/, "")

    clean_code = "article-#{column.id}" if clean_code.blank?

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
      **(column.code.present? ? {} : { code: clean_code })
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
    prompt = <<~PROMPT
      以下の記事情報からSEO向けメタ情報をJSON形式で生成してください。

      【記事タイトル】
      #{column.title}

      【業種】
      #{category}

      【記事テーマ】
      #{column.prompt}

      【重要】
      - サービス宣伝記事にしない
      - 比較サイトのような記事にしない
      - 中立的なSEO記事にする
      - 誇張禁止
      - 汎用記事として成立させる
      - 読者課題を主軸にする
      - 業界調査型の記事にする
      - descriptionは自然なSEO説明文
      - codeは英語スラッグ
      - JSON以外禁止

      【業界情報】
      #{build_industry_context(genre_data, sub_data)}

      【EEAT強化情報】
      #{eeat_context}

      出力形式:
      {
        "code": "english-slug",
        "description": "日本語説明",
        "keyword": "SEOキーワード"
      }
    PROMPT

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

    prompt = <<~PROMPT
      以下の記事のH2構成をJSON形式で生成してください。

      【記事タイトル】
      #{column.title}

      【業種】
      #{category}

      【関連子記事】
      #{child_titles.join("\n")}

      【記事方針】
      - 中立的な情報記事
      - サービス誘導禁止
      - 比較サイト化禁止
      - 業界分析型にする
      - 実務目線で構成
      - 現場課題を解説
      - SEOテンプレ禁止
      - 「おすすめ」「ランキング」禁止
      - ノウハウ型記事にする
      - 業界理解が深まる構成にする
      - 各H2は異なる論点・異なる結論を扱うこと（同じ主張の言い換え禁止）
      - 各H2について、想定される結論の性質（例: "KPI定義の統一", "責任分界の明確化", "データ受け渡しルール", "教育・再現性の担保" など）を conclusion_type として付与する
      - conclusion_type が同じH2が3つ以上連続しないよう、見出しの切り口を調整する

      【業界背景】
      #{build_industry_context(genre_data, sub_data)}

      【EEAT強化情報】
      #{eeat_context}

      【出力条件】
      - H2は4〜7個の範囲で、テーマの複雑さに応じて過不足なく設計する（網羅性を優先して見出しを増やさない。読者の意思決定に必要な論点だけに絞る）
      - 全て日本語
      - 見出しのみ
      - SEOワードを自然に含める
      - 汎用的な構成にする
      - 各H2について、以下のいずれかに該当する場合は has_table を true にしてよい（無理な絞り込みは不要）
        (a) 複数の項目を軸で比較・分類する内容 → 本文側で表として表現される
        (b) 確認すべき項目・実施すべき手順・揃えるべき条件のように、Yes/No的にチェックできる内容 → 本文側でチェックリストとして表現される
      - 判断軸や心構え・注意点の解説など、文章のみで十分伝わる見出しは無理に true にせず false のままにする
      - JSON以外禁止

      出力形式:
      {
        "structure": [
          { "h2_title": "見出し", "has_table": false }
        ]
      }
    PROMPT

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

      content.gsub!(/\A```[a-z]*\n/i, "")
      content.gsub!(/```\z/m, "")

      content.strip
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

    system_content = <<~SYSTEM
      あなたはSEO記事専門ライターです。

      【最重要ルール】
      - 日本語のみ
      - 中立的に解説
      - サービス販売ページ化禁止
      - 比較サイト化禁止
      - 誇張禁止
      - 業界構造を解説する
      - 一次情報ベースの文体
      - 実務レベルで解説
      - AI臭い文章禁止
      - PREP法固定禁止
      - 箇条書き乱用禁止
      - 体験談風の嘘を作らない
      - 「この記事では」禁止
      - 「おすすめです」連発禁止
      - 業界メディア品質で書く
      - 専門性と網羅性を重視
      - Google EEATを意識
      - 他セクションで述べた結論・ロジックの再掲禁止（新しい論点・情報を追加すること）
      - 表・チェックリストの指示がある場合のみMarkdown記法を使用し、それ以外では表記法を使わない
      【文末表現の多様化（厳守）】
      - 「〜が重要です」「〜が実務的です」「〜が求められます」を1セクション内で2回以上使うことを禁止する
      - 結論文は、断定（〜になる／〜が起きる）、具体例の提示、問いかけ、条件提示など異なる形式を混在させる
    SYSTEM

    if json_mode
      system_content += "\n出力はJSONのみ。"
    else
      system_content += "\n本文テキストのみ出力。"
      system_content += "\nJSON禁止。"
      system_content += "\n見出し出力禁止。"
    end

    system_content = GptGenerationLocale.resolve_system_prompt(system_content, json_mode: json_mode)

    payload = {
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
      temperature: 0.45
    }

    payload[:response_format] = {
      type: "json_object"
    } if json_mode

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

  # ==========================================================
  # 導入文
  # ==========================================================
  def self.introduction_prompt(column, category, genre_data, sub_data, eeat_context)
    <<~PROMPT
      「#{column.title}」の記事導入文を作成してください。

      【条件】
      - 日本語
      - 700〜1100文字
      - SEO記事として自然に
      - 中立的に解説
      - 業界背景から入る
      - 読者課題から始める
      - サービス宣伝禁止
      - AIテンプレ禁止
      - 見出し禁止
      - 汎用記事として成立させる
      - 専門メディア品質で執筆

      【業界背景】
      #{build_industry_context(genre_data, sub_data)}

      【EEAT強化情報】
      #{eeat_context}

      【追加指示】
      #{column.prompt}
    PROMPT
  end

  # ==========================================================
  # H2本文（has_table対応）
  # ==========================================================
  def self.h2_content_prompt(column, category, section, genre_data, sub_data, eeat_context, covered_points = [])
    <<~PROMPT
      以下H2見出しの本文を執筆してください。

      【記事タイトル】
      #{column.title}

      【見出し】
      #{section["h2_title"]}

      #{build_covered_points_block(covered_points)}

      #{build_table_instruction(section)}

      【禁止ルール（厳守）】
      - 書き出しの一言目に「#{section["h2_title"]}は、」や「#{section["h2_title"]}において、」など、見出しの言葉をそのまま主語としてオウム返しする不自然な解説開始文を「絶対に禁止」します。文脈から自然に書き出してください。
      - 上記【既出セクションの要旨】に記載された主張・結論・具体例と同じ内容を繰り返すことを「絶対に禁止」します。この見出し特有の新しい論点・視点・情報を中心に書いてください。

      【セクション末尾の書き方】
      - 最後の1〜2文は、「〜が重要です」「〜が実務的です」のような一般原則の再掲で終えず、具体的な数値・条件・チェック項目・失敗例のいずれかで締めること
      - 全体の結論（責任分界や情報連携の重要性など）に触れる場合は、この見出し固有の切り口（例：KPIの話なら分母定義、契約の話なら成果対象の置き方）に紐づけた形でのみ言及してよい

      【条件】
      - 日本語
      - 900〜1400文字（テーマの核心に必要な具体例・実務背景のみを扱い、無理な水増しはしない。表やチェックリストを入れる場合、その文字数も含めてよい）
      - 専門性を持たせる
      - 実務視点で解説
      - 中立的に解説
      - 比較サイト化禁止
      - 宣伝禁止
      - 「弊社では」禁止
      - AIテンプレ禁止
      - PREP法固定禁止
      - 見出しを本文に含めない
      - 実際の業界構造を解説
      - 表面的説明で終わらせない
      - 業界背景まで掘り下げる
      - EEATを意識する
      - 現場理解が伝わる文章にする

      【業界背景】
      #{build_industry_context(genre_data, sub_data)}

      【EEAT強化情報】
      #{eeat_context}

      【追加指示】
      #{column.prompt}
    PROMPT
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
    <<~PROMPT
      「#{column.title}」の記事まとめを執筆してください。

      #{build_covered_points_block(covered_points)}

      【セクション末尾の書き方】
      - 最後の1〜2文は、「〜が重要です」のような一般原則の再掲で終えず、記事全体を通じて得られた具体的な視点や確認すべき観点で締めること

      【条件】
      - 「## まとめ」から開始
      - 日本語
      - 中立的
      - 宣伝禁止
      - 誇張禁止
      - 記事全体を自然に総括
      - 業界全体の視点で締める
      - SEO記事として自然に終える
      - 汎用記事として成立させる
      - 上記【既出セクションの要旨】を踏まえ、各セクションの言い換えではなく統合的な総括にする
      - まとめでは表・チェックリストは使用しない(通常の文章のみ)

      【業界背景】
      #{build_industry_context(genre_data, sub_data)}

      【EEAT強化情報】
      #{eeat_context}

      【追加指示】
      #{column.prompt}
    PROMPT
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