require "net/http"
require "json"
require "openssl"
require "openai"

class GptArticleGenerator
  class GenerationCancelledError < StandardError; end

  MODEL_NAME = "gpt-4o-mini"
  MAX_RETRIES = 3 # 本文が抽出されない、または文字数が足りない場合のリトライ回数

  GPT_API_KEY = ENV["GPT_API_KEY"]
  GPT_API_URL = "https://api.openai.com/v1/chat/completions"

  def self.generate_body(column)
    unless GPT_API_KEY.present?
      Rails.logger.error("OPENAI_API_KEY が設定されていません")
      return nil
    end

    original_body = column.body

    # ==============================
    # GenreRegistryを用いたジャンル特定ロジック
    # ==============================
    genre_code = if GenreRegistry::GENRES.key?(column.genre&.to_sym)
                   column.genre.to_s
                 elsif (code = GenreRegistry.from_ja(column.genre))
                   code
                 else
                   detect_genre_code(column.keyword)
                 end

    genre_data = GenreRegistry::GENRES[genre_code.to_sym] || {}
    category = genre_data[:ja] || GenreRegistry.to_ja(genre_code) || "その他"

    # ==============================
    # サブカテゴリ判定
    # ==============================
    sub_genre_code = detect_sub_category(column, genre_code)
    sub_data = (genre_data[:sub_categories] && sub_genre_code) ? genre_data[:sub_categories][sub_genre_code.to_sym] : nil

    Rails.logger.info("判定カテゴリ: #{category} (コード: #{genre_code}, サブ: #{sub_genre_code})")

    # ==============================
    # EEATコンテキスト構築
    # ==============================
    eeat_context = build_eeat_context(column, genre_data, sub_data)

    # ==============================
    # STEP 0: meta情報生成 & DBステータス正常化
    # ==============================
    ensure_not_cancelled!(column)
    meta_data = generate_meta_info(column, category, genre_data, sub_data, eeat_context)
    if meta_data
      clean_code = meta_data["code"].to_s.downcase.gsub(/[^a-z0-9\s\-]/, '').strip.gsub(/[\s_]+/, '-').gsub(/-+/, '-').gsub(/\A-|-\z/, '')
      clean_code = "article-#{column.id.to_s.split('-').first}" if clean_code.blank?
      
      column.update!(
        genre: genre_code,
        sub_genre: sub_genre_code,
        code: clean_code,
        description: meta_data["description"],
        keyword: meta_data["keyword"]
      )
      begin
        FluxImageGeneratorService.generate!(column)
      rescue => e
        Rails.logger.error "[FluxImageGeneration] #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end

    # ==============================
    # STEP 1: 構成生成
    # ==============================
    ensure_not_cancelled!(column)
    structure_data = generate_structure(column, category, genre_data, sub_data, eeat_context)
    return original_body if structure_data.nil?

    structure = structure_data["structure"] || []
    return original_body if structure.length < 3

    # ==============================
    # STEP 2: 本文生成（リトライ機能付き）
    # ==============================
    full_article = ""

    # 導入文の生成（想定: 700〜1100文字）
    ensure_not_cancelled!(column)
    intro_prompt_text = introduction_prompt(column, category, genre_data, sub_data, eeat_context)
    full_article += generate_section_content_with_retry(
      "導入",
      intro_prompt_text,
      column,
      min_length: 600,
      json_mode: false
    ) + "\n\n"

    # 各H2見出しの本文生成（想定: 1200〜1800文字）
    structure.each do |h2|
      ensure_not_cancelled!(column)
      next if h2["h2_title"].blank?
      
      full_article += "## #{h2['h2_title']}\n\n"

      h2_prompt_text = h2_content_prompt(column, category, h2, genre_data, sub_data, eeat_context)
      full_article += generate_section_content_with_retry(
        h2["h2_title"],
        h2_prompt_text,
        column,
        min_length: 1000,
        json_mode: false
      ) + "\n\n"

      sleep(0.5) 
    end

    # まとめ文の生成（プロンプト側で「## まとめ」を出力させるため、ここでは見出しを結合しない）
    ensure_not_cancelled!(column)
    conclusion_prompt_text = conclusion_prompt(column, category, genre_data, sub_data, eeat_context)
    full_article += generate_section_content_with_retry(
      "まとめ",
      conclusion_prompt_text,
      column,
      min_length: 300,
      json_mode: false
    )

    # 後処理フォーマット調整
    full_article.gsub!(/\s+id=(['"])[^'"]*\1/i, "")
    full_article.gsub!(/<(h[23])[^>]*>/i, '<\1>')
    full_article += "\n\n{::options auto_ids=\"false\" /}"
    full_article
  end

  def self.generate_section_content_with_retry(name, prompt, column, min_length: 50, json_mode: false)
    MAX_RETRIES.times do |i|
      ensure_not_cancelled!(column)
      response = call_gpt_api(prompt, json_mode: json_mode)
      content = response&.dig("choices", 0, "message", "content")
      
      if content.present? && content.strip.length >= min_length
        return content.strip
      end

      Rails.logger.warn("#{name} の本文が抽出できない、または文字数が足りないためリトライします（制限: #{min_length}文字以上） (#{i+1}/#{MAX_RETRIES})")
      sleep(1)
    end
    "（#{name}の本文生成に失敗しました。再生成してください。）"
  end

  def self.ensure_not_cancelled!(column)
    column.reload
    if column.generation_status == "cancelled"
      raise GenerationCancelledError, "記事生成がユーザー操作で停止されました"
    end
  end

  def self.detect_genre_code(keyword)
    return "other" if keyword.blank?
    GenreRegistry::GENRES.each do |key, data|
      if data[:keywords].any? { |w| keyword.include?(w) }
        return key.to_s
      end
    end
    "other"
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
    Rails.logger.error("Meta生成エラー: #{e.message}")
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
    Rails.logger.error("構成生成エラー: #{e.message}")
    nil
  end

  # ==========================================================
  # 導入文
  # ==========================================================
  def self.introduction_prompt(column, category, genre_data, sub_data, eeat_context)
    <<~PROMPT
      「#{column.title}」の記事導入文を作成してください。

      【条件】
      - 日本語のみで出力
      - 700〜1100文字を厳守（詳細な背景解説を行うこと）
      - SEO記事として自然に
      - 中立的に解説
      - 業界背景から入る
      - 読者課題から始める
      - サービス宣伝禁止
      - AIテンプレ禁止
      - 見出し（#や##など）は一切出力禁止、本文のみ
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
  def self.h2_content_prompt(column, category, section, genre_data, sub_data, eeat_context)
    <<~PROMPT
      以下H2見出しの本文を執筆してください。

      【記事タイトル】
      #{column.title}

      【対象見出し】
      #{section["h2_title"]}

      【禁止ルール（厳守）】
      - 書き出しの一言目に「#{section["h2_title"]}は、」や「#{section["h2_title"]}において、」など、見出しの言葉をそのまま主語としてオウム返しする不自然な解説開始文を「絶対に禁止」します。文脈から自然に書き出してください。

      【条件】
      - 日本語のみで出力
      - 1200〜1800文字を厳守（具体例や現場の課題、実務背景を多角的に掘り下げて分量を満たすこと）
      - 専門性を持たせる
      - 実務視点で解説
      - 中立的に解説
      - 比較サイト化禁止
      - 宣伝禁止
      - 「弊社では」「当サービスでは」など自社への言及は一切禁止
      - AIテンプレ禁止
      - PREP法固定禁止
      - 見出しマークアップ（##や###）を本文内に含めない
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
  # まとめ
  # ==========================================================
  def self.conclusion_prompt(column, category, genre_data, sub_data, eeat_context)
    <<~PROMPT
      「#{column.title}」の記事まとめを執筆してください。

      【条件】
      - 必ず「## まとめ」という見出し文字列から開始してください。
      - 日本語のみで出力
      - 中立的
      - 宣伝禁止
      - 誇張禁止
      - 文字数：300〜500文字を維持
      - 記事全体を自然に総括
      - 業界全体の視点で締める
      - SEO記事として自然に終える
      - 汎用記事として成立させる

      【業界背景】
      #{build_industry_context(genre_data, sub_data)}

      【EEAT強化情報】
      #{eeat_context}

      【追加指示】
      #{column.prompt}
    PROMPT
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

  # ==========================================================
  # GPT API
  # ==========================================================
  def self.call_gpt_api(prompt, json_mode: false)
    uri = URI(GPT_API_URL)
    req = Net::HTTP::Post.new(uri)

    req["Content-Type"] = "application/json"
    req["Authorization"] = "Bearer #{GPT_API_KEY}"

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
    SYSTEM

    if json_mode
      system_content += "\n出力はJSONのみ。"
    else
      system_content += "\n本文テキストのみ出力。"
      system_content += "\nJSON禁止。"
      system_content += "\n見出し出力禁止（指示された場合を除く）。"
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
        read_timeout: 300
      ) do |http|
        http.request(req)
      end

      if res.is_a?(Net::HTTPSuccess)
        JSON.parse(res.body)
      else
        Rails.logger.error "❌ OpenAI Error: #{res.code} #{res.body}"
        nil
      end
    rescue => e
      Rails.logger.error "❌ API Exception: #{e.message}"
      nil
    end
  end
end