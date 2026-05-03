require "net/http"
require "json"
require "openssl"

class GptPillarGenerator
  MODEL_NAME = "gpt-4o-mini"
  GPT_API_URL = "https://api.openai.com/v1/chat/completions"

  # ==========================================================
  # メイン生成ロジック
  # ==========================================================
  def self.generate_full_from_existing_column!(column)
    raise "タイトルが空です" if column.title.blank?
    
    # GenreRegistryを使用してカテゴリとジャンルコードを特定
    target_category = detect_category(column)
    genre_code = GenreRegistry.from_ja(target_category) || "other"

    puts "▶ 統合生成開始: #{column.title} (判定: #{target_category})"

    # 1. meta情報生成 (JSONモード / リトライ付)
    meta_data = nil
    3.times do |i|
      res = generate_meta_info(column, target_category)
      if res
        meta_data = res
        break
      end
      puts "⚠️ Meta生成失敗 再試行中... (#{i+1}/3)"
      sleep(2)
    end
    raise "Meta情報の生成に失敗しました" if meta_data.nil?
    
    # スラッグのクレンジング
    clean_code = meta_data["code"].to_s.downcase
                  .gsub(/[^a-z0-9\s\-]/, '')
                  .strip
                  .gsub(/[\s_]+/, '-')
                  .gsub(/-+/, '-')
                  .gsub(/\A-|-\z/, '')

    clean_code = "article-#{column.id.to_s.split('-').first}" if clean_code.blank?

    # 2. 記事構成生成 (JSONモード / リトライ付)
    structure_data = nil
    3.times do |i|
      res = generate_structure(column, target_category)
      if res && res["structure"].present?
        structure_data = res
        break
      end
      puts "⚠️ 構成生成失敗 再試行中... (#{i+1}/3)"
      sleep(2)
    end
    raise "記事構成の生成に失敗しました" if structure_data.nil?

    # DB中間保存
    column.update!(
      code: clean_code,
      description: meta_data["description"],
      keyword: meta_data["keyword"],
      choice: target_category,
      genre: genre_code,
      status: "creating",
      article_type: "pillar"
    )

    # 3. 本文生成
    body_content = ""
    
    # 導入文
    body_content += call_text_section(introduction_prompt(column, target_category)) + "\n\n"

    # 各見出し
    structure_data["structure"].each do |section|
      h2_title = section["h2_title"]
      body_content += "## #{h2_title}\n\n"
      
      # セクション本文の生成
      section_body = call_text_section(h2_content_prompt(column, target_category, section))
      
      # 重複見出しの徹底除去
      section_body.gsub!(/\A\s*#+\s+#{Regexp.escape(h2_title)}\s*\n+/i, "")
      section_body.gsub!(/\A\s*#{Regexp.escape(h2_title)}\s*\n+/i, "")
      
      body_content += section_body + "\n\n"
      sleep(1.5)
    end

    # まとめ
    body_content += call_text_section(conclusion_prompt(column, target_category))
    body_content += "\n\n{::options auto_ids=\"false\" /}"

    # 4. 最終保存
    column.update!(
      body: body_content,
      status: "completed" 
    )

    puts "✅ 生成完了: #{clean_code}"
    true
  end

  private

  def self.detect_category(column)
    search_text = "#{column.title} #{column.keyword} #{column.genre} #{column.choice}"
    
    # GenreRegistry内の全キーワードを走査して判定
    GenreRegistry::GENRES.each do |key, data|
      if data[:keywords].any? { |w| search_text.include?(w) }
        return data[:ja]
      end
    end
    
    "その他"
  end

  def self.generate_meta_info(column, category)
    prompt = <<~PROMPT
      以下の条件でSEOメタ情報を「JSON」形式で生成してください。
      【重要】説明文(description)は必ず日本語、スラッグ(code)のみ英語にしてください。
      
      タイトル: #{column.title}
      業種: #{category}
      #{column.prompt.present? ? "追加指示: #{column.prompt}" : ""}
      出力形式: { "code": "english-slug", "description": "日本語の説明文", "keyword": "キーワード" }
    PROMPT
    res = call_gpt_api(prompt, json_mode: true)
    res ? JSON.parse(res.dig("choices", 0, "message", "content")) : nil
  rescue
    nil
  end

  def self.generate_structure(column, category)
    child_columns = Column.where(parent_id: column.id, article_type: "child")
    child_titles = child_columns.map(&:title).join("\n- ")
    prompt = <<~PROMPT
      記事「#{column.title}」の構成（日本語のH2見出し6〜8個）を「JSON」形式で作成してください。
      業種: #{category}
      子記事リスト: #{child_titles}
      #{column.prompt.present? ? "【最優先指示】この記事の中核となる内容: #{column.prompt}" : ""}
      出力形式: { "structure": [ { "h2_title": "日本語の見出し名" } ] }
    PROMPT
    res = call_gpt_api(prompt, json_mode: true)
    res ? JSON.parse(res.dig("choices", 0, "message", "content")) : nil
  rescue
    nil
  end

  def self.call_text_section(prompt)
    max_retries = 3
    retries = 0
    begin
      response = call_gpt_api(prompt, json_mode: false)
      content = response&.dig("choices", 0, "message", "content")
      
      raise "Content is empty" if content.blank?
      
      # クレンジング処理
      content.gsub!(/\A```[a-z]*\n/i, '') # 開始のコードブロック除去
      content.gsub!(/```\z/m, '')        # 終了のコードブロック除去
      content.gsub!(/\A\{.*"content":\s*"/m, '') # 万が一JSONが混ざった場合の開始除去
      content.gsub!(/"\s*\}\z/m, '')              # 万が一JSONが混ざった場合の終了除去
      content.strip
    rescue => e
      retries += 1
      if retries < max_retries
        puts "⚠️ 本文生成失敗 再試行中... (#{retries}/#{max_retries})"
        sleep(2)
        retry
      end
      "（生成エラー：このセクションの生成に失敗しました。再実行してください）"
    end
  end

  def self.call_gpt_api(prompt, json_mode: false)
    uri = URI(GPT_API_URL)
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["Authorization"] = "Bearer #{ENV['GPT_API_KEY']}"

    system_content = "あなたはSEO専門ライターです。回答は【必ず日本語】で行ってください。"
    system_content += " 出力はJSON形式で行ってください。" if json_mode
    system_content += " JSONは禁止です。そのまま本文として使えるプレーンテキストのみ出力してください。見出しは一切生成しないでください。" unless json_mode

    payload = {
      model: MODEL_NAME,
      messages: [
        { role: "system", content: system_content },
        { role: "user", content: prompt }
      ],
      temperature: 0.3
    }
    payload[:response_format] = { type: "json_object" } if json_mode
    req.body = payload.to_json

    begin
      # read_timeoutを300秒に延長
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 300) { |http| http.request(req) }
      
      if res.is_a?(Net::HTTPSuccess)
        JSON.parse(res.body)
      else
        nil
      end
    rescue => e
      nil
    end
  end

  def self.introduction_prompt(column, category)
    prompt_base = "記事「#{column.title}」の導入文を日本語で600文字以上執筆してください。JSON形式は厳禁です。"
    column.prompt.present? ? "#{prompt_base}\nなお、以下の内容を導入文の軸としてください:#{column.prompt}" : prompt_base
  end

  def self.h2_content_prompt(column, category, section)
    prompt_base = "見出し「#{section["h2_title"]}」の本文を日本語で1000文字程度執筆してください。業種「#{category}」に関連させ、JSONは使わずテキストのみ出力してください。【重要】「## #{section["h2_title"]}」のような見出し自体は絶対に本文に含めないでください。本文のみを開始してください。"
    column.prompt.present? ? "#{prompt_base}\n以下の核となる方針を必ず反映させてください:#{column.prompt}" : prompt_base
  end

  def self.conclusion_prompt(column, category)
    prompt_base = "記事「#{column.title}」のまとめを日本語で執筆してください。必ず「## まとめ」から開始し、JSONは使わないでください。"
    column.prompt.present? ? "#{prompt_base}\n最後に、以下の内容を総括に含めてください:#{column.prompt}" : prompt_base
  end
end