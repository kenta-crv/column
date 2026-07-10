require "net/http"
require "json"
require "openssl"

class GptPillarGenerator
  class GenerationCancelledError < StandardError; end

  MODEL_NAME = "gpt-5.4-nano"
  GPT_API_URL = "https://api.openai.com/v1/chat/completions"

  # 公開前に人によるレビューを挟みたい場合は true にする。
  # true の場合、生成完了後のステータスは "completed" ではなく
  # "review_pending" になり、画像生成などの後続処理はスキップされる。
  # （既存の運用を壊さないよう、デフォルトは false = 従来どおり即公開）
  REQUIRE_HUMAN_REVIEW = false

  # 記事内で同じ「論理パターン」が繰り返されるのを防ぐための
  # 検出用正規表現。マッチした場合、そのカテゴリを次のセクション
  # プロンプトに「既出」として渡し、別の説明方法を使わせる。
  REPEATED_ARGUMENT_PATTERNS = {
    single_metric_warning: /だけ.{0,12}(追う|見る|管理|判断).{0,20}(落ち|歪|下が|崩れ|見えにく|ズレ)/,
    kpi_breakdown_generic: /(架電数|接続率|商談化率).{0,10}(だけでなく|のみならず)/,
    definition_ambiguous_warning: /(定義|基準).{0,10}(曖昧|揃って).{0,15}(ズレ|崩れ|混乱)/
  }.freeze

  # H2セクションごとに異なる「構造スタイル」を巡回させ、
  # 全セクションが同じベタ書き構成にならないようにする。
  SECTION_STYLES = [:comparison_table, :ordered_list, :mini_scenario, :plain].freeze

  # ==========================================================
  # メイン生成ロジック
  # ==========================================================
  def self.generate_full_from_existing_column!(column)
    raise "タイトルが空です" if column.title.blank?
    ensure_not_cancelled!(column)

    target_category = detect_category(column)
    current_genre   = column.genre.presence || GenreRegistry.from_ja(target_category) || "other"

    puts "▶ 統合生成開始: #{column.title} (判定: #{target_category}, genre: #{current_genre})"

    # ----------------------------------------------------------
    # Genre情報取得
    # ----------------------------------------------------------
    genre_data = GenreRegistry::GENRES[current_genre.to_sym] || {}
    sub_key    = detect_sub_category(column, current_genre)
    sub_data   = genre_data.dig(:sub_categories, sub_key.to_sym) rescue nil

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

      puts "⚠️ Meta生成失敗 再試行中... (#{i + 1}/3)"
      sleep(2)
    end

    raise "Meta情報の生成に失敗しました" if meta_data.nil?

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
    covered_points = []       # ← 既出セクションの要旨（重複防止用）
    used_argument_types = []  # ← 既出セクションで使われた「論理パターン」の種類

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

    # 目次
    body_content += "## 目次\n\n"

    structure_data["structure"].each do |section|
      ensure_not_cancelled!(column)
      body_content += "- #{section["h2_title"]}\n"
    end

    body_content += "\n"

    total_sections = structure_data["structure"].size

    # H2セクション
    structure_data["structure"].each_with_index do |section, index|
      ensure_not_cancelled!(column)
      h2_title = section["h2_title"]

      body_content += "## #{h2_title}\n\n"

      style = SECTION_STYLES[index % SECTION_STYLES.size]

      section_body = call_text_section(
        h2_content_prompt(
          column,
          target_category,
          section,
          genre_data,
          sub_data,
          eeat_context,
          covered_points,
          used_argument_types,
          style
        )
      )

      section_body.gsub!(/\A\s*#+\s+#{Regexp.escape(h2_title)}\s*\n+/i, "")
      section_body.gsub!(/\A\s*#{Regexp.escape(h2_title)}\s*\n+/i, "")

      body_content += section_body
      body_content += "\n\n"

      # このセクションの要旨を記録し、次のセクション生成時に「既出」として渡す
      covered_points << {
        title: h2_title,
        gist: extract_gist(section_body)
      }

      # このセクションで使われた論理パターンを記録
      used_argument_types |= detect_argument_types(section_body)

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

    final_status = REQUIRE_HUMAN_REVIEW ? "review_pending" : "completed"

    column.update!(
      body: body_content,
      status: final_status
    )

    if final_status == "completed"
      begin
        FluxImageGeneratorService.generate!(column)
      rescue => e
        Rails.logger.error "[FluxImageGeneration] column #{column.id}: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
      end
    else
      puts "⏸ レビュー待ちのため画像生成はスキップしました: #{clean_code}"
    end

    puts "✅ 生成完了 (status=#{final_status}): #{clean_code}"

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
  # サブカテゴリ判定
  # ==========================================================
  def self.detect_sub_category(column, genre_key)
    genre = GenreRegistry::GENRES[genre_key.to_sym]
    return nil unless genre
    return nil unless genre[:sub_categories]

    text = [
      column.title,
      column.keyword,
      column.prompt,
      column.description
    ].join(" ")

    genre[:sub_categories].each do |key, sub|
      next unless sub[:keywords]

      if sub[:keywords].any? { |w| text.include?(w) }
        return key.to_s
      end
    end

    nil
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

    JSON.parse(
      res.dig("choices", 0, "message", "content")
    )
  rescue => e
    puts "❌ generate_meta_info parse error: #{e.message}"
    nil
  end

  # ==========================================================
  # 構成生成
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
      - 各H2は「何を比較・判断する軸なのか」が一目でわかるタイトルにすること
      - 少なくとも1つのH2は、複数の選択肢を横並びで整理できる論点にすること
        （例: 運用モデル別、料金体系別、業種別など。比較表を作りやすい構成にする）

      【業界背景】
      #{build_industry_context(genre_data, sub_data)}

      【EEAT強化情報】
      #{eeat_context}

      【出力条件】
      - H2を6〜8個
      - 全て日本語
      - 見出しのみ
      - SEOワードを自然に含める
      - 汎用的な構成にする
      - JSON以外禁止

      出力形式:
      {
        "structure": [
          { "h2_title": "見出し" }
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
  def self.call_gpt_api(prompt, json_mode: false)
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
      - 「〜が重要です」「〜が欠かせません」「〜が必要です」等の結び表現を
        同一セクション内で2回以上使わない。表現にバリエーションを持たせる
      - 具体的な統計や金額を書く場合、断定的な事実であるかのように書かない。
        「一般的な目安として」「現場でよく見られる例として」等でヘッジする。
        実在しない出典を捏造しない
    SYSTEM

    if json_mode
      system_content += "\n出力はJSONのみ。"
    else
      system_content += "\n本文テキストのみ出力。"
      system_content += "\nJSON禁止。"
      system_content += "\n見出し出力禁止。"
    end

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
        JSON.parse(res.body)
      else
        puts "❌ OpenAI Error: #{res.code} #{res.body}"
        nil
      end
    rescue => e
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
  # H2本文
  # ==========================================================
  def self.h2_content_prompt(column, category, section, genre_data, sub_data, eeat_context, covered_points = [], used_argument_types = [], style = :plain)
    <<~PROMPT
      以下H2見出しの本文を執筆してください。

      【記事タイトル】
      #{column.title}

      【見出し】
      #{section["h2_title"]}

      #{build_covered_points_block(covered_points)}

      #{build_argument_avoidance_block(used_argument_types)}

      #{build_style_instruction(style)}

      【条件】
      - 日本語
      - 1200〜1800文字
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
      - 上記【既出セクションの要旨】と同じ主張・結論・具体例を繰り返さない
      - この見出し特有の新しい論点・視点・情報を中心に書く
      - 【既出の論理パターン】に挙げたものと同じ「警告の型」を再利用しない。
        使うなら、具体例・数値レンジ・ミニケースなど別の説明方法に置き換える

      【業界背景】
      #{build_industry_context(genre_data, sub_data)}

      【EEAT強化情報】
      #{eeat_context}

      【追加指示】
      #{column.prompt}
    PROMPT
  end

  # ==========================================================
  # まとめ
  # ==========================================================
  def self.conclusion_prompt(column, category, genre_data, sub_data, eeat_context, covered_points = [])
    <<~PROMPT
      「#{column.title}」の記事まとめを執筆してください。

      #{build_covered_points_block(covered_points)}

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

      【業界背景】
      #{build_industry_context(genre_data, sub_data)}

      【EEAT強化情報】
      #{eeat_context}

      【追加指示】
      #{column.prompt}
    PROMPT
  end

  # ==========================================================
  # セクション構造スタイルの指示ブロック
  # ==========================================================
  def self.build_style_instruction(style)
    case style
    when :comparison_table
      <<~TEXT
        【この見出しの構成指示】
        本文中に、Markdown形式の比較表を1つ含めること。
        例: | 項目 | パターンA | パターンB |
        表の前後に地の文で解説を加え、表だけで終わらせない。
        表の数値・分類は断定的な統計として書かず、
        整理・分類のための一般的な目安として提示すること。
      TEXT
    when :ordered_list
      <<~TEXT
        【この見出しの構成指示】
        判断基準または確認事項を、番号付きリスト（1. 2. 3.）で
        3〜5項目に整理する部分を本文中に含めること。
        リストの前後に地の文の解説を加え、リストだけで終わらせない。
      TEXT
    when :mini_scenario
      <<~TEXT
        【この見出しの構成指示】
        「たとえば〜のようなケースでは」という形で、
        具体的な業務シーン（架空の一般化された例でよい）を
        1つ挙げて説明すること。実在の企業名は使わない。
      TEXT
    else
      <<~TEXT
        【この見出しの構成指示】
        通常の説明文で構成してよいが、他の見出しと
        同じ文章パターン（導入→定義→注意点→まとめ、等）を
        繰り返さないこと。
      TEXT
    end
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
  # 既出の論理パターン回避ブロック生成
  # ==========================================================
  def self.build_argument_avoidance_block(used_argument_types)
    return "" if used_argument_types.blank?

    labels = used_argument_types.map { |t| argument_type_label(t) }

    <<~TEXT
      【既出の論理パターン（同じ型を再利用しない）】
      #{labels.map { |l| "- #{l}" }.join("\n")}
    TEXT
  end

  def self.argument_type_label(type)
    {
      single_metric_warning: "単一指標だけで判断すると危険、という警告構文",
      kpi_breakdown_generic: "複数KPIを並べて「これだけでなく」と注意喚起する構文",
      definition_ambiguous_warning: "定義や基準の曖昧さがズレを生む、という警告構文"
    }[type] || type.to_s
  end

  # ==========================================================
  # セクション要旨の抽出（次セクションへの重複防止用）
  # ==========================================================
  def self.extract_gist(section_body)
    return "" if section_body.blank?

    sentences = section_body.split(/(?<=。)/).map(&:strip).reject(&:blank?)
    return "" if sentences.empty?

    # 冒頭2文（何を論じ始めたか）+ 末尾1文（結論・要旨）を要旨として使う。
    # 追加API呼び出しを避けつつ、中盤〜終盤の結論も拾えるようにする簡易実装。
    lead = sentences.first(2)
    tail = sentences.length > 2 ? [sentences.last] : []

    (lead + tail).uniq.join("").truncate(220)
  end

  # ==========================================================
  # セクション内の「論理パターン」を検出
  # ==========================================================
  def self.detect_argument_types(section_body)
    return [] if section_body.blank?

    REPEATED_ARGUMENT_PATTERNS.each_with_object([]) do |(type, pattern), found|
      found << type if section_body.match?(pattern)
    end
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