require "net/http"
require "json"
require "openssl"
require "openai"

class GptArticleGenerator
  TARGET_CHARS_PER_SECTION = 300
  MAX_CHARS_PER_SECTION = 500
  MODEL_NAME = "gpt-4o-mini"
  MAX_RETRIES = 3 # 本文が抽出されない場合のリトライ回数

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

    sub_genre = column.respond_to?(:sub_genre) ? column.sub_genre : nil
    category = GenreRegistry.to_ja(genre_code) || "その他"
    user_instruction = column.respond_to?(:prompt) ? column.prompt : nil

    Rails.logger.info("判定カテゴリ: #{category} (コード: #{genre_code}, サブ: #{sub_genre})")

    # ==============================
    # STEP 0: meta情報生成 & DBステータス正常化
    # ==============================
    meta_data = generate_meta_info(column, category)
    if meta_data
      clean_code = meta_data["code"].to_s.downcase.gsub(/[^a-z0-9\s\-]/, '').strip.gsub(/[\s_]+/, '-').gsub(/-+/, '-').gsub(/\A-|-\z/, '')
      clean_code = "article-#{column.id.to_s.split('-').first}" if clean_code.blank?
      
      column.update!(
        genre: genre_code,
        code: clean_code,
        description: meta_data["description"],
        keyword: meta_data["keyword"]
      )
    end

    # ==============================
    # STEP 1: 構成生成
    # ==============================
    structure_prompt = structure_generation_prompt(column, genre_code, sub_genre, user_instruction)
    structure_response = call_gpt_api(structure_prompt, response_format: { type: "json_object" })

    return original_body if structure_response.nil?

    begin
      json_str = structure_response.dig("choices", 0, "message", "content")
      structure_data = JSON.parse(json_str)
      structure = structure_data["structure"] || []

      return original_body if structure.length < 3
    rescue => e
      Rails.logger.error("構成生成エラー: #{e.message}")
      return original_body
    end

    # ==============================
    # STEP 2: 本文生成（リトライ機能付き）
    # ==============================
    full_article = ""
    overall_structure_text = structure.map.with_index(1) { |s, i| "#{i}. #{s['h2_title']}" }.join("\n")

    full_article += generate_section_content_with_retry(
      "導入",
      introduction_prompt(column, genre_code, sub_genre, user_instruction, overall_structure_text),
      column,
      heading_level: ""
    ) + "\n\n"

    structure.each do |h2|
      full_article += "## #{h2['h2_title']}\n\n"

      if h2["h3_sub_sections"].present?
        h2["h3_sub_sections"].each do |h3|
          prompt = section_content_prompt(column, h3, "H3", genre_code, sub_genre, user_instruction, parent_h2: h2["h2_title"], overall_structure: overall_structure_text)
          full_article += generate_section_content_with_retry(h3, prompt, column, heading_level: "###") + "\n\n"
          sleep(0.5) 
        end
      else
        prompt = section_content_prompt(column, h2["h2_title"], "H2", genre_code, sub_genre, user_instruction, overall_structure: overall_structure_text)
        full_article += generate_section_content_with_retry(h2["h2_title"], prompt, column, heading_level: "") + "\n\n"
      end

      sleep(0.5) 
    end

    full_article += generate_section_content_with_retry(
      "まとめ",
      simple_conclusion_prompt(column, genre_code, sub_genre, user_instruction, overall_structure_text),
      column,
      heading_level: ""
    )
    full_article.gsub!(/\s+id=(['"])[^'"]*\1/i, "")
    full_article.gsub!(/<(h[23])[^>]*>/i, '<\1>')
    full_article += "\n\n{::options auto_ids=\"false\" /}"
    full_article
  end

  def self.generate_section_content_with_retry(name, prompt, column, heading_level: "##")
    MAX_RETRIES.times do |i|
      response = call_gpt_api(prompt)
      content = response&.dig("choices", 0, "message", "content")
      
      if content.present? && content.strip.length > 50
        return content
      end

      Rails.logger.warn("#{name} の本文が抽出できなかったため、リトライします (#{i+1}/#{MAX_RETRIES})")
      sleep(1)
    end
    "（#{name}の本文生成に失敗しました。再生成してください。）"
  end

  def self.generate_meta_info(column, category)
    prompt = <<~PROMPT
      以下の条件でSEOメタ情報をJSONで生成してください。
      タイトル: #{column.title}
      業種: #{category}
      形式: { "code": "slug", "description": "日本語説明", "keyword": "キーワード" }
    PROMPT
    res = call_gpt_api(prompt, response_format: { type: "json_object" })
    res ? JSON.parse(res.dig("choices", 0, "message", "content")) : nil
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

  def self.structure_generation_prompt(column, genre_code, sub_genre, user_instruction)
    category_ja = GenreRegistry.to_ja(genre_code) || "その他"
    instruction = user_instruction.present? ? "### 個別指示（最優先事項）\n#{user_instruction}\n" : ""
    <<~PROMPT
      あなたはSEO専門ライターです。読者の検索意図を解決する一般的かつ論理的な構成をJSONで作ってください。
      
      # 記事情報
      - タイトル: #{column.title}
      - 業種カテゴリ: #{category_ja}
      #{instruction}

      # 構成指示（厳守）
      1. 読者が知りたい「ノウハウ・一般論」を網羅した見出しを立ててください。
      2. 「自社の強み」や紹介に特化した見出しは、全体の最後に1つ程度に留めてください。
      3. 各セクションの内容が絶対に重複しないよう役割を分担してください。

      # 出力形式
      { "structure": [ { "h2_title": "...", "h3_sub_sections": ["..."] } ] }
    PROMPT
  end

  def self.introduction_prompt(column, genre_code, sub_genre, user_instruction, overall_structure)
    instruction = user_instruction.present? ? "### 個別指示（反映必須）\n#{user_instruction}\n" : ""
    <<~PROMPT
      タイトル「#{column.title}」の導入文を#{TARGET_CHARS_PER_SECTION}文字以上で書いてください。
      
      # 記事全体の構成案
      #{overall_structure}

      - 役割：読者の悩みへの共感と、記事を読むメリット。
      - 注意：自社サービスの宣伝、サービス名は「絶対に」出さないでください。専門家の視点でフラットに執筆してください。
      #{instruction}
      - 見出しは含めず本文のみ出力してください。
    PROMPT
  end

  def self.section_content_prompt(column, headline, level, genre_code, sub_genre, user_instruction, parent_h2: nil, overall_structure: nil)
    parent = parent_h2 ? "（親テーマ: #{parent_h2}）" : ""
    service_raw = GenreRegistry.service_profile(genre_code, sub_genre)
    # ラベルを除去して名称のみを抽出
    service_name = service_raw.split("\n").first.gsub("サービス名: ", "").strip
    instruction = user_instruction.present? ? "### 個別指示（最優先事項）\n#{user_instruction}\n" : ""
    heading_instr = level == "H3" ? "### #{headline} から書き始めてください。" : "本文のみ書いてください。"

    <<~PROMPT
      以下のセクションを執筆してください。
      見出し: #{headline} #{parent}
      
      # 執筆の絶対ルール
      1. **専門的な一般論**: 300文字〜500文字で、業界の標準的な知識を詳しく解説してください。
      2. **自社名の出し方**: 「サービス名：」のような不自然な接頭辞は「厳禁」です。
      3. **言及の制限**: この見出しが「コスト」「人材」「品質管理」に関する場合のみ、「一般的な業者は〜ですが、#{service_name}では〜」という比較の形で、一箇所だけ自然に織り交ぜてください。
      4. **上記以外**: 文脈に合わない場合は自社名（#{service_name}）を「一切出さない」でください。全ての見出しに自社名を出すのは「絶対に禁止」です。
      5. **重複の排除**: 他の見出しで書く予定の内容を避け、この見出し独自の専門知識を深掘りしてください。
      
      #{heading_instr}
      #{instruction}
    PROMPT
  end

  def self.simple_conclusion_prompt(column, genre_code, sub_genre, user_instruction, overall_structure)
    service_raw = GenreRegistry.service_profile(genre_code, sub_genre)
    service_name = service_raw.split("\n").first.gsub("サービス名: ", "").strip
    instruction = user_instruction.present? ? "### 個別指示（反映必須）\n#{user_instruction}\n" : ""
    <<~PROMPT
      記事「#{column.title}」の総括（まとめ）を執筆してください。
      
      # 記事全体の構成案
      #{overall_structure}

      - 必ず「## まとめ」という見出しから開始してください。
      - 記事全体をフラットに振り返り、読者の不安を解消する内容にしてください。
      - 最後の一節でのみ、専門サービス「#{service_name}」への相談を促してください。
      - 「サービス名：」という表記は「厳禁」です。
      #{instruction}
      - 文字数：必ず300〜500文字を維持してください。
    PROMPT
  end

  def self.call_gpt_api(prompt, response_format: nil)
    uri = URI(GPT_API_URL)
    req = Net::HTTP::Post.new(uri, { "Content-Type" => "application/json", "Authorization" => "Bearer #{GPT_API_KEY}" })

    payload = {
      model: MODEL_NAME,
      messages: [
        { role: "system", content: "あなたはプロの業界ライターです。見出しを出力した際は、必ずセットで300文字以上の具体的かつ重複のない本文を執筆します。不自然なラベル（サービス名：等）は一切使いません。" },
        { role: "user", content: prompt }
      ],
      temperature: 0.4
    }

    payload[:response_format] = response_format if response_format.present?
    req.body = payload.to_json

    begin
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 240) do |http|
        http.request(req)
      end
      res.is_a?(Net::HTTPSuccess) ? JSON.parse(res.body) : nil
    rescue => e
      Rails.logger.error("GPT API通信エラー: #{e.message}")
      nil
    end
  end
end