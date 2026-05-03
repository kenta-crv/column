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
    # 1. 英字コード(genre_code)を特定する
    genre_code = if GenreRegistry::GENRES.key?(column.genre&.to_sym)
                   column.genre.to_s
                 elsif (code = GenreRegistry.from_ja(column.genre))
                   code
                 else
                   # キーワードから推測
                   detect_genre_code(column.keyword)
                 end

    # 2. 日本語カテゴリ名の特定
    category = GenreRegistry.to_ja(genre_code) || "その他"
    
    user_instruction = column.respond_to?(:prompt) ? column.prompt : nil

    Rails.logger.info("判定カテゴリ: #{category} (コード: #{genre_code})")

    # ==============================
    # STEP 0: meta情報生成 & DBステータス正常化
    # ==============================
    meta_data = generate_meta_info(column, category)
    if meta_data
      clean_code = meta_data["code"].to_s.downcase.gsub(/[^a-z0-9\s\-]/, '').strip.gsub(/[\s_]+/, '-').gsub(/-+/, '-').gsub(/\A-|-\z/, '')
      clean_code = "article-#{column.id.to_s.split('-').first}" if clean_code.blank?
      
      # genre を英字コードで保存
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
    structure_prompt = structure_generation_prompt(column, category, user_instruction)
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
      introduction_prompt(column, category, user_instruction, overall_structure_text),
      column,
      heading_level: ""
    ) + "\n\n"

    structure.each do |h2|
      full_article += "## #{h2['h2_title']}\n\n"

      if h2["h3_sub_sections"].present?
        h2["h3_sub_sections"].each do |h3|
          prompt = section_content_prompt(column, h3, "H3", category, user_instruction, parent_h2: h2["h2_title"], overall_structure: overall_structure_text)
          full_article += generate_section_content_with_retry(h3, prompt, column, heading_level: "###") + "\n\n"
          sleep(0.5) 
        end
      else
        prompt = section_content_prompt(column, h2["h2_title"], "H2", category, user_instruction, overall_structure: overall_structure_text)
        full_article += generate_section_content_with_retry(h2["h2_title"], prompt, column, heading_level: "") + "\n\n"
      end

      sleep(0.5) 
    end

    full_article += generate_section_content_with_retry(
      "まとめ",
      simple_conclusion_prompt(column, category, user_instruction, overall_structure_text),
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

  # ジャンルレジストリのキーワードから該当するジャンルキーを返す
  def self.detect_genre_code(keyword)
    return "other" if keyword.blank?

    GenreRegistry::GENRES.each do |key, data|
      if data[:keywords].any? { |w| keyword.include?(w) }
        return key.to_s
      end
    end

    "other"
  end

  def self.structure_generation_prompt(column, category, user_instruction)
    service = GenreRegistry.service_profile(category)
    instruction = user_instruction.present? ? "### 個別指示（最優先事項）\n#{user_instruction}\n" : ""
    <<~PROMPT
      あなたはプロの業界特化ライターです。読者の疑問を段階的に解消する論理的な構成をJSONで作成してください。

      # 記事情報
      - タイトル: #{column.title}
      - 業種カテゴリ: #{category}
      - サービス背景: #{service}
      #{instruction}

      # 構成指示（厳守）
      - 各セクションの内容が絶対に重複しないよう役割を分担してください。
      - 300文字以上の「本文」を執筆できる深掘り可能な見出しを設定してください。
      - 本文を書く内容がないような薄い見出しは作成しないでください。

      # 出力形式
      { "structure": [ { "h2_title": "...", "h3_sub_sections": ["..."] } ] }
    PROMPT
  end

  def self.introduction_prompt(column, category, user_instruction, overall_structure)
    service = GenreRegistry.service_profile(category)
    instruction = user_instruction.present? ? "### 個別指示（反映必須）\n#{user_instruction}\n" : ""
    <<~PROMPT
      タイトル「#{column.title}」の導入文を書いてください。
      
      # 記事全体の構成案
      #{overall_structure}

      - 役割：読者の悩みへの共感と、記事を読むメリット。
      - 注意：具体的な結論（数値等）は後の見出しで詳述するため、ここでは期待感を高める内容に留め、重複を避けてください。
      #{instruction}
      - 文字数：必ず#{TARGET_CHARS_PER_SECTION}文字以上を維持してください。
      - 見出しは含めず本文のみ出力してください。
    PROMPT
  end

  def self.section_content_prompt(column, headline, level, category, user_instruction, parent_h2: nil, overall_structure: nil)
    parent = parent_h2 ? "（親テーマ: #{parent_h2}）" : ""
    service = GenreRegistry.service_profile(category)
    instruction = user_instruction.present? ? "### 個別指示（最優先事項）\n#{user_instruction}\n" : ""
    heading_instr = level == "H3" ? "### #{headline} から書き始めてください。" : "本文のみ書いてください。"

    <<~PROMPT
      以下のセクションを執筆してください。見出しだけ出力して本文を省略することは「絶対に禁止」です。

      # 全体の構成案
      #{overall_structure}

      - 見出し: #{headline} #{parent}
      - タイトル: #{column.title}
      - 専門背景: #{service}
      #{instruction}

      # 執筆の絶対ルール
      1. **本文執筆の義務**: 必ず300文字〜500文字の本文を生成してください。
      2. **重複の徹底排除**: 他の見出しで書く予定の内容を避け、この見出し独自の専門知識を深掘りしてください。
      3. **一貫性**: 記事全体の構成に沿った論理的な文章にしてください。
      
      #{heading_instr}
    PROMPT
  end

  def self.simple_conclusion_prompt(column, category, user_instruction, overall_structure)
    service = GenreRegistry.service_profile(category)
    instruction = user_instruction.present? ? "### 個別指示（反映必須）\n#{user_instruction}\n" : ""
    <<~PROMPT
      記事「#{column.title}」の総括（まとめ）を執筆してください。
      
      # 記事全体の構成案
      #{overall_structure}

      - 必ず「## まとめ」という見出しから開始してください。
      - 記事全体を振り返り、読者の不安を解消する内容にしてください。
      - 最後に、専門サービス「#{service.split("\n").first}」へ相談することを具体的なアクションとして促してください。
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
        { role: "system", content: "あなたはプロの業界ライターです。見出しを出力した際は、必ずセットで300文字以上の具体的かつ重複のない本文を執筆します。本文の省略や見出しのみの出力は絶対にしません。" },
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