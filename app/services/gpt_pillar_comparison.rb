require "net/http"
require "json"
require "openssl"
require "uri"

# ==========================================================
# 【テスト版:比較記事専用・汎用版】
# 既存の gpt_pillar_generator.rb をそのまま差し替えて使うテスト版。
# クラス名・メソッド名は既存と完全に同一。
#
# 前バージョンからの修正:
# - VERIFIED_FACTS(会社固有の事実の決め打ちテキスト)を廃止した。
#   直書きするのは OWN_COMPANY_URL(と任意で OWN_COMPANY_NAME)の
#   1箇所だけであり、別の会社でテストしたい場合はこの1行を
#   書き換えるだけで済む。
# - 事実は毎回 web_fetch でそのURLから取得する。取得できなければ
#   「事実なし」として扱い、古い/別会社の情報で埋め合わせることは
#   一切しない。
# - 事実が取得できなかった場合、company/recommendation軸では
#   具体的な数値・機能名を創作せず、一般的なトーンに留める設計。
# ==========================================================
class GptPillarComparison
  class GenerationCancelledError < StandardError; end

  MODEL_NAME = "gpt-5.4-nano"
  GPT_API_URL = "https://api.openai.com/v1/chat/completions"

  CLAUDE_API_URL = "https://api.anthropic.com/v1/messages"
  CLAUDE_MODEL   = "claude-sonnet-4-6"

  # ----------------------------------------------------------
  # 【直書きするのはこの1行だけ】
  # 別サービスでテストする場合はURLを書き換えるだけでよい。
  # 会社名は任意(空ならURLのドメインから自動生成する)。
  # ----------------------------------------------------------
  OWN_COMPANY_URL  = "https://okurite.pro/okurite"
  OWN_COMPANY_NAME = nil # 空ならドメインから自動生成

  # ==========================================================
  # メイン生成ロジック
  # ==========================================================
  def self.generate_full_from_existing_column!(column)
    raise "タイトルが空です" if column.title.blank?
    ensure_not_cancelled!(column)

    client = column.client
    target_category = detect_category(column)
    current_genre   = column.genre.presence || GenreRegistry.from_ja(target_category) || "other"

    company_name = resolve_company_name

    puts "▶ 統合生成開始(比較記事・汎用版): #{column.title} (判定: #{target_category}, genre: #{current_genre})"

    genre_data = GenreRegistry.genre_entry(current_genre, client: client) || {}
    sub_key    = GenreRegistry.resolve_sub_category_key(column, current_genre, client: client)
    sub_data   = sub_key.present? ? genre_data.dig(:sub_categories, sub_key.to_sym) : nil

    # ----------------------------------------------------------
    # 事実の確定:web_fetchでの直接取得のみを信頼する。
    # 取得できなければ nil のまま(埋め合わせの決め打ち事実は使わない)。
    # ----------------------------------------------------------
    web_facts = fetch_web_facts_strict(OWN_COMPANY_URL)

    puts(web_facts.present? ? "✅ Web直接取得の事実を使用" : "ℹ️ Web取得なし。事実は使わず一般的なトーンで自社言及する")

    effective_prompt = build_effective_prompt(column, company_name, web_facts)

    eeat_context = build_eeat_context(column, genre_data, sub_data, company_name)

    # ----------------------------------------------------------
    # Meta生成
    # ----------------------------------------------------------
    meta_data = nil

    3.times do |i|
      ensure_not_cancelled!(column)
      res = generate_meta_info(column, target_category, genre_data, sub_data, eeat_context, effective_prompt)

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
    # 構成生成(comparison_axis付き)
    # ----------------------------------------------------------
    structure_data = nil

    3.times do |i|
      ensure_not_cancelled!(column)
      res = generate_structure(column, target_category, genre_data, sub_data, eeat_context, effective_prompt, company_name)

      if res.present? && res["structure"].present?
        structure_data = res
        break
      end

      puts "⚠️ 構成生成失敗 再試行中... (#{i + 1}/3)"
      sleep(2)
    end

    raise "記事構成の生成に失敗しました" if structure_data.nil?

    column.update!(
      description: meta_data["description"],
      keyword: meta_data["keyword"],
      choice: target_category,
      genre: current_genre,
      status: "creating",
      **(column.article_type.present? ? {} : { article_type: "pillar" }),
      **column.seo_code_assignment(clean_code)
    )

    # ----------------------------------------------------------
    # 本文生成
    # ----------------------------------------------------------
    body_content = ""
    covered_points = []

    ensure_not_cancelled!(column)
    body_content += call_text_section(
      introduction_prompt(column, target_category, genre_data, sub_data, eeat_context, effective_prompt)
    )

    body_content += "\n\n## #{GptGenerationLocale.toc_heading}\n\n"

    structure_data["structure"].each do |section|
      body_content += "- #{section["h2_title"]}\n"
    end

    body_content += "\n"

    # 頻出フレーズを記事全体で追跡するカウンタ(セクションをまたいで蓄積)
    phrase_counts = Hash.new(0)

    structure_data["structure"].each do |section|
      ensure_not_cancelled!(column)
      h2_title = section["h2_title"]

      body_content += "## #{h2_title}\n\n"

      overused_block = build_overused_phrases_block(phrase_counts)
      axis_scoped_prompt = build_axis_scoped_prompt(column, company_name, web_facts, section["comparison_axis"])

      section_body = call_text_section(
        h2_content_prompt(column, target_category, section, genre_data, sub_data, eeat_context, covered_points, axis_scoped_prompt, company_name, web_facts.present?, overused_block)
      )

      section_body.gsub!(/\A\s*#+\s+#{Regexp.escape(h2_title)}\s*\n+/i, "")
      section_body.gsub!(/\A\s*#{Regexp.escape(h2_title)}\s*\n+/i, "")
      section_body = sanitize_markdown_table(section_body)
      section_body = strip_internal_labels(section_body)

      body_content += section_body
      body_content += "\n\n"

      covered_points << { title: h2_title, gist: extract_gist(section_body) }
      track_phrase_frequency!(phrase_counts, section_body)

      sleep(1.2)
    end

    ensure_not_cancelled!(column)
    conclusion_body = call_text_section(
      conclusion_prompt(column, target_category, genre_data, sub_data, eeat_context, covered_points, effective_prompt)
    )
    body_content += strip_internal_labels(conclusion_body)

    body_content += "\n\n{::options auto_ids=\"false\" /}"

    ensure_not_cancelled!(column)
    column.update!(body: body_content, status: "completed")

    puts "✅ 生成完了(比較記事・汎用版): #{clean_code}"

    true
  end

  def self.ensure_not_cancelled!(column)
    return unless GenerateColumnBodyJob.cancelled?(column.id)

    raise GenerationCancelledError, "記事生成がユーザー操作で停止されました"
  end

  private

  # ==========================================================
  # 自社名の解決:OWN_COMPANY_NAMEが空ならドメインから自動生成
  # ==========================================================
  def self.resolve_company_name
    return OWN_COMPANY_NAME if OWN_COMPANY_NAME.present?

    host = URI.parse(OWN_COMPANY_URL).host rescue nil
    return "自社サービス" if host.blank?

    host.split(".").first.to_s.capitalize
  end

  # ==========================================================
  # カテゴリ判定(既存と同一)
  # ==========================================================
  def self.detect_category(column)
    search_text = [column.title, column.keyword, column.genre, column.choice].join(" ")

    GenreRegistry::GENRES.each do |_, data|
      next unless data[:keywords]

      if data[:keywords].any? { |w| search_text.include?(w) }
        return data[:ja]
      end
    end

    "その他"
  end

  # ==========================================================
  # web_fetchで指定URLを直接取得する(検索は使わない)。
  # allowed_domainsで、指定URLのドメイン以外は一切参照できないよう
  # 技術的に制限する。取得できなければ nil を返すのみで、
  # 埋め合わせの決め打ち事実は一切使わない。
  # ==========================================================
  def self.fetch_web_facts_strict(target_url)
    return nil if target_url.blank?

    domain = URI.parse(target_url).host rescue nil
    return nil if domain.blank?

    puts "🔎 Web直接取得(web_fetch)開始: #{target_url} (許可ドメイン: #{domain})"

    prompt = <<~PROMPT
      web_fetchツールを使って、次のURLのページ内容を直接取得してください。
      検索(web_search)は使わないでください。このURL以外のページや、
      似た名前の別サービス・別会社の情報は一切参照・使用しないでください。

      取得対象URL: #{target_url}

      【出力条件】
      - 実際にこのURLから取得できた内容に基づく事実だけを、日本語の箇条書きで出力する
      - 料金・プラン、具体的な件数・数値、機能・技術的特徴、会社情報、導入実績など
      - このURLの取得に失敗した場合、または内容がサービス説明として不十分な場合は、
        他の情報で埋め合わせず、「取得失敗」という1行だけを出力する
      - 前置き・後書きは不要。箇条書き、または「取得失敗」の1行のみ出力する
    PROMPT

    res = call_claude_api(
      prompt,
      use_web_fetch: true,
      allowed_domains: [domain]
    )

    return nil unless res

    text_blocks = res["content"].to_a.select { |c| c["type"] == "text" }.map { |c| c["text"] }
    facts = text_blocks.join("\n").strip

    if facts.blank? || facts.include?("取得失敗") || facts.length < 30
      puts "⚠️ Web直接取得: 有効な事実が取得できませんでした(#{facts.length}文字)"
      return nil
    end

    puts "✅ Web直接取得完了(#{facts.length}文字)"
    facts
  rescue => e
    puts "❌ fetch_web_facts_strict error: #{e.message}"
    nil
  end

  # ==========================================================
  # column.prompt + 自社情報 を、comparison_axisに応じて出し分ける。
  # - "company"/"recommendation" 軸: 自社の事実(web_facts)を含めてよい
  # - "method" 軸: 自社名・自社の事実を一切含めない(method軸への
  #   事実の漏れ出しが、記事全体での機能名の過剰な繰り返しの
  #   原因になっていたため、ここで構造的に断つ)
  # ==========================================================
  def self.build_axis_scoped_prompt(column, company_name, web_facts, axis)
    base = column.prompt.presence || ""

    if axis == "method"
      <<~TEXT
        #{base}

        【この見出しについての注意】
        - この見出しは手法・方式の比較であり、自社(#{company_name})の名称や、
          自社固有の機能名・サービス名を、この見出しの中で出さないこと
        - 一般的な業界の考え方・手法として比較する
      TEXT
    else
      parts = [base, "自社：#{company_name}(#{OWN_COMPANY_URL})"]

      if web_facts.present?
        parts << <<~TEXT
          【自社(#{company_name})のWeb直接取得による確認済み事実(この範囲内でのみ使用可)】
          #{web_facts}
        TEXT
      else
        parts << <<~TEXT
          【注意】自社(#{company_name})について、Webから具体的な事実(料金・件数・機能名等)は
          取得できていない。したがって、自社への言及は一般的なトーンに留め、
          具体的な数値・機能名・プラン名は一切創作しないこと。
        TEXT
      end

      parts.join("\n")
    end
  end

  # ==========================================================
  # column.prompt + 自社情報(URLのみ固定) + web_facts(取得できた場合のみ)
  # を統合した「実効プロンプト」を作る
  # ==========================================================
  def self.build_effective_prompt(column, company_name, web_facts)
    parts = []
    parts << column.prompt if column.prompt.present?

    parts << "自社：#{company_name}(#{OWN_COMPANY_URL})"

    if web_facts.present?
      parts << <<~TEXT
        【自社(#{company_name})のWeb直接取得による確認済み事実(この範囲内でのみ使用可)】
        #{web_facts}
      TEXT
    else
      parts << <<~TEXT
        【注意】自社(#{company_name})について、Webから具体的な事実(料金・件数・機能名等)は
        取得できていない。したがって、自社への言及は一般的なトーン(業界の課題にどう応えるか、
        どんな考え方で運用を組み立てているか等)に留め、具体的な数値・機能名・プラン名は
        一切創作しないこと。
      TEXT
    end

    parts.join("\n")
  end

  # ==========================================================
  # EEATコンテキスト(比較記事版)
  # ==========================================================
  def self.build_eeat_context(column, genre_data, sub_data, company_name)
    contexts = []

    contexts << "記事ジャンル: #{genre_data[:ja]}" if genre_data[:ja].present?

    if genre_data[:keywords].present?
      contexts << "関連キーワード: #{genre_data[:keywords].join('、')}"
    end

    if sub_data.present?
      contexts << "対象読者: #{sub_data[:target]}" if sub_data[:target].present?
      contexts << "業界説明: #{sub_data[:description]}" if sub_data[:description].present?

      if sub_data[:features].present?
        contexts << "この業界特有の比較軸として必ず活用すること(method軸・recommendation軸のどちらでも使ってよい): #{sub_data[:features].join('、')}"
      end

      if sub_data[:industry_weakness].present?
        contexts << "業界課題(比較の切り口、および自社がどう応えられるかの文脈で使ってよい): #{sub_data[:industry_weakness]}"
      end
    end

    contexts << <<~TEXT
      以下を重視して執筆すること:
      - この記事は「比較記事」であり、通常のノウハウ記事とは性質が異なる
      - 比較軸・判断基準を具体的に示す
      - 実務レベルで説明する
      - 現場視点を含める
      - 【追加指示】内に確認済み事実がある場合、それを積極的に具体的な料金・件数・実績として使う
      - 確認済み事実がない場合、自社(#{company_name})の具体的な数値・機能名を創作しない
      - 情報が不足している旨や、調査プロセスに関する記述(「Web検索で確認できる情報が限定的だった」等)を本文に書かない
      - 自社(#{company_name})への言及は必ずどこか1箇所以上のH2で行うこと
      - 他社比較の最終着地は自社(#{company_name})の推薦であること。他社を並列の最終候補として並べて終わらないこと
    TEXT

    contexts.join("\n")
  end

  # ==========================================================
  # SEOメタ生成(比較記事版)
  # ==========================================================
  def self.generate_meta_info(column, category, genre_data, sub_data, eeat_context, effective_prompt)
    prompt = <<~PROMPT
      以下の記事情報からSEO向けメタ情報をJSON形式で生成してください。

      【記事タイトル】
      #{column.title}

      【業種】
      #{category}

      【記事テーマ】
      #{effective_prompt}

      【重要】
      - この記事は比較記事として作成する
      - 読者が選択・意思決定するための記事であることを前提にする
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
  # 構成生成(比較記事版:comparison_axisを判定させる)
  # ==========================================================
  def self.generate_structure(column, category, genre_data, sub_data, eeat_context, effective_prompt, company_name)
    child_columns = Column.where(parent_id: column.id, article_type: "child")
    child_titles = child_columns.map(&:title)

    prompt = <<~PROMPT
      以下の記事のH2構成をJSON形式で生成してください。

      【記事タイトル】
      #{column.title}

      【業種】
      #{category}

      【追加指示(自社情報・確認済み事実を含む)】
      #{effective_prompt}

      【関連子記事】
      #{child_titles.join("\n")}

      【記事方針】
      - この記事は比較記事である
      - 各H2は、以下のいずれかを判定して comparison_axis に付与する
        - "company": 実在企業名を比較する見出し
        - "method": 手法・方式・条件を比較する見出し
        - "recommendation": 自社サービスへの言及・推薦を行う見出し
      - 【追加指示】に実在企業名や具体的事実が明記されている場合のみ comparison_axis を "company" にしてよい
      - 明記がない場合は "company" にせず、下記EEAT強化情報のfeatures(業界特有の比較軸)を使った "method" として構成する
      - 最後のH2、または「まとめ」に近い位置に、comparison_axis: "recommendation" のH2を必ず1つ含める
        (見出し自体で自社#{company_name}を選ぶべき理由が分かるようにする。中立的な「選び方の切り分け」だけで終わらせない)
      - 各H2は異なる論点・異なる結論を扱うこと

      【業界背景】
      #{build_industry_context(genre_data, sub_data)}

      【EEAT強化情報】
      #{eeat_context}

      【出力条件】
      - H2は4〜7個
      - 全て日本語
      - 見出しのみ
      - 各H2について、比較・条件整理に該当する場合は has_table を true にしてよい
      - JSON以外禁止

      出力形式:
      {
        "structure": [
          { "h2_title": "見出し", "has_table": false, "comparison_axis": "method" }
        ]
      }
    PROMPT

    res = call_gpt_api(prompt, json_mode: true)

    return nil unless res

    JSON.parse(res.dig("choices", 0, "message", "content"))
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
  # 内部ラベル漏れ除去(既存と同一の安全策)
  # ==========================================================
  def self.strip_internal_labels(text)
    return text if text.blank?

    text
      .gsub(/[（(]\s*comparison_axis\s*[:：]?\s*["']?(company|method|recommendation)["']?\s*[）)]/i, "")
      .gsub(/[（(]\s*(company|method|recommendation)\s*軸\s*[）)]/i, "")
      .gsub(/comparison_axis/i, "")
      .gsub(/Web検索で確認できる情報が限定的だったため[^。]*。/, "")
      .gsub(/公開情報(の範囲|ベース)で(は)?[^。]*。/, "")
  end

  # ==========================================================
  # GPT API(本文執筆用)
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
      .gsub(/sk-ant-[a-zA-Z0-9_\-]+/, "[REDACTED_KEY]")
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
      あなたはSEO記事専門ライターです。この記事は「比較記事」として作成します。

      【最重要ルール】
      - 日本語のみ
      - 実務レベルで解説
      - 業界メディア品質で書く
      - 他セクションで述べた結論の再掲禁止
      - 表・チェックリストの指示がある場合のみMarkdown記法を使用

      【比較記事特有のルール(厳守)】
      - ユーザーの【追加指示】に明記されていない実在企業名・料金・機能・実績を創作しない
      - 【追加指示】内に確認済み事実がある場合、そこに書かれた料金・件数・実績は積極的に具体的に使ってよい
      - 確認済み事実がない場合、自社の機能名・料金・件数・プラン名・実績数値を一切創作しない
      - 【追加指示】に自社サービスの情報がある場合、比較の文脈の中で自然に推薦してよい
      - 他社について、根拠のない誹謗・貶める表現は使わない
      - 比較は事実ベースで行い、誇張表現を避ける
      - 業界特有の比較軸(features)を積極的に判断材料として使う

      【出力形式に関する絶対禁止事項(厳守)】
      - comparison_axis という単語や、company/method/recommendation という
        内部分類名・ラベルを本文に一切出力しない
      - 「(company軸)」「(recommendation軸)」のような括弧書きを本文に書かない
      - 「Web検索で確認できる情報が限定的だった」「公開情報の範囲で」のような、
        調査プロセスや情報の限界について本文で言及しない

      【文末表現の多様化(厳守)】
      - 「〜が重要です」「〜が実務的です」を1セクション内で2回以上使わない

      【語句レベルの重複回避(厳守)】
      - プロンプト内に「表現の重複回避」という指示ブロックがある場合、そこに列挙された語句・言い回しを
        そのまま繰り返さず、必ず別の表現に言い換える。同じ機能・概念を指す場合でも、毎回同じ固有の
        フレーズで説明せず、言葉のバリエーションを持たせること
    SYSTEM

    if json_mode
      system_content += "\n出力はJSONのみ。"
    else
      system_content += "\n本文テキストのみ出力。"
      system_content += "\nJSON禁止。"
      system_content += "\n見出し出力禁止。"
    end

    system_content = GptGenerationLocale.resolve_system_prompt(system_content, json_mode: json_mode)

    payload = GptGenerationLocale.chat_completions_payload(
      model: MODEL_NAME,
      messages: [
        { role: "system", content: system_content },
        { role: "user", content: prompt }
      ],
      json_mode: json_mode,
      temperature: 0.45
    )

    req.body = payload.to_json

    begin
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 120) do |http|
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
  # Claude API(事実収集専用)
  # ==========================================================
  def self.call_claude_api(prompt, use_web_search: false, use_web_fetch: false, allowed_domains: nil)
    uri = URI(CLAUDE_API_URL)

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["x-api-key"] = ENV["ANTHROPIC_API_KEY"]
    req["anthropic-version"] = "2023-06-01"

    payload = {
      model: CLAUDE_MODEL,
      max_tokens: 1500,
      messages: [
        { role: "user", content: prompt }
      ]
    }

    if use_web_fetch
      tool = { type: "web_fetch_20250910", name: "web_fetch", max_uses: 3 }
      tool[:allowed_domains] = allowed_domains if allowed_domains.present?
      payload[:tools] = [tool]
    elsif use_web_search
      payload[:tools] = [
        { type: "web_search_20250305", name: "web_search" }
      ]
    end

    req.body = payload.to_json

    begin
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 120) do |http|
        http.request(req)
      end

      if res.is_a?(Net::HTTPSuccess)
        JSON.parse(res.body)
      else
        puts "❌ Claude API Error: #{res.code} #{redact_secrets(res.body.to_s)}"
        nil
      end
    rescue => e
      puts "❌ Claude API Exception: #{e.message}"
      nil
    end
  end

  # ==========================================================
  # 導入文(比較記事版)
  # ==========================================================
  def self.introduction_prompt(column, category, genre_data, sub_data, eeat_context, effective_prompt)
    <<~PROMPT
      「#{column.title}」の記事導入文を作成してください。

      【条件】
      - 日本語
      - 700〜1100文字
      - この記事は比較記事であることを前提に、読者が「何を基準に選べばよいか」で悩んでいる状況から書き出す
      - 業界背景から入る
      - AIテンプレ禁止
      - 見出し禁止
      - 専門メディア品質で執筆

      【業界背景】
      #{build_industry_context(genre_data, sub_data)}

      【EEAT強化情報】
      #{eeat_context}

      【追加指示】
      #{effective_prompt}
    PROMPT
  end

  # ==========================================================
  # H2本文(比較記事版)
  # has_facts が false(事実未取得)の場合、company/recommendation軸でも
  # 具体的数値を創作しないよう追加の注意を強める
  # ==========================================================
  def self.h2_content_prompt(column, category, section, genre_data, sub_data, eeat_context, covered_points, effective_prompt, company_name, has_facts, overused_block = "")
    axis = section["comparison_axis"]

    fact_guard =
      if has_facts
        "【追加指示】の確認済み事実に書かれた範囲でのみ、具体的な数値・機能名を使ってよい。"
      else
        "自社について確認済みの具体的事実がない状態である。料金・件数・機能名・プラン名などの具体的な数値は一切創作せず、一般的なトーン(考え方・方針レベル)に留めること。"
      end

    axis_instruction =
      case axis
      when "company"
        <<~TEXT
          【この見出しの内部方針:企業比較(本文には出さない内部メモ)】
          - 【追加指示】に明記された実在企業・確認済み事実の範囲内でのみ比較を行うこと
          - 【追加指示】に書かれていない企業名、料金、機能、実績を創作してはならない
          - 他社について、根拠のない断定的な批判・誹謗にあたる表現は使わない。事実ベースで淡々と特徴を並べる
        TEXT
      when "recommendation"
        <<~TEXT
          【この見出しの内部方針:自社推薦(本文には出さない内部メモ)】
          - #{fact_guard}
          - ここまでの比較を踏まえ、最終的に自社(#{company_name})を推す見出しとして書く
          - 「用途によって他社も候補」で終わらせず、なぜ自社が第一候補かを比較軸に沿って説明する
          - 誇張表現は避け、他社を過度に貶める表現は使わない
        TEXT
      else
        <<~TEXT
          【この見出しの内部方針:手法・方式の比較(本文には出さない内部メモ)】
          - 実在企業名は出さず、方式・条件・アプローチの違いとして比較する
          - 下記EEAT強化情報のfeatures(業界特有の比較軸)を積極的に判断基準として使うこと
        TEXT
      end

    <<~PROMPT
      以下H2見出しの本文を執筆してください。

      【記事タイトル】
      #{column.title}

      【見出し】
      #{section["h2_title"]}

      #{axis_instruction}

      #{build_covered_points_block(covered_points)}

      #{overused_block}

      #{build_table_instruction(section)}

      【出力に関する絶対禁止事項(厳守)】
      - 見出しの分類名("company"や"method"、"recommendation"、comparison_axisという単語)を本文に出力しない
      - 「(◯◯軸)」のような分類を示す括弧書きを本文に含めない
      - 確認済み事実に無い自社の機能名・プラン名・料金・件数を創作しない
      - 情報が不十分である旨や、調査の過程についての記述を本文に書かない

      【禁止ルール(厳守)】
      - 見出しの言葉をそのまま主語としてオウム返しする書き出しを禁止する
      - 上記【既出セクションの要旨】と同じ内容の繰り返しを禁止する

      【セクション末尾の書き方】
      - 最後の1〜2文は、具体的な判断基準・条件・チェックポイントで締めること

      【条件】
      - 日本語
      - 900〜1400文字
      - 比較の判断軸を明確にする
      - 現場理解が伝わる文章にする

      【業界背景】
      #{build_industry_context(genre_data, sub_data)}

      【EEAT強化情報】
      #{eeat_context}

      【追加指示】
      #{effective_prompt}
    PROMPT
  end

  # ==========================================================
  # 表・チェックリスト生成指示ブロック(既存と同一)
  # ==========================================================
  def self.build_table_instruction(section)
    if section["has_table"]
      <<~TEXT
        【表・チェックリストの挿入(必須・どちらか1つを選ぶ)】
        この見出しの内容に応じて、以下のどちらかを1つだけ選んで本文中の適切な位置に挿入してください。両方入れない。

        ■ 表(Markdownテーブル)を選ぶ基準:
          - 複数の項目を「軸」で比較・分類する内容
          - `| 項目 | 内容 |` のようなパイプ区切りのMarkdownテーブル形式を使用
          - ヘッダー行の直下に `|---|---|` の区切り行を必ず入れる
          - 各行の列数(パイプの数)は必ず揃える

        ■ チェックリストを選ぶ基準:
          - 「確認すべき項目」「作業前に揃えるべき条件」など、Yes/No的に確認・実施できる内容
          - この基準に該当する場合は、必ず `- [ ] 項目` の形式を使用する

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
  # まとめ(比較記事版)
  # ==========================================================
  def self.conclusion_prompt(column, category, genre_data, sub_data, eeat_context, covered_points = [], effective_prompt)
    <<~PROMPT
      「#{column.title}」の記事まとめを執筆してください。

      #{build_covered_points_block(covered_points)}

      【出力に関する絶対禁止事項(厳守)】
      - comparison_axisという単語や、"company"/"method"/"recommendation"という分類名を本文に出力しない
      - 確認済み事実に無い情報や、調査の限界についての言及を書かない

      【条件】
      - 「## まとめ」から開始
      - 日本語
      - 300〜500文字
      - 比較を踏まえた最終着地として、自社サービスを第一候補として推薦して締める
      - 他社を並列の最終候補として並べて終わらないこと(他社は比較の材料として触れるに留める)
      - 表・チェックリストは使用しない

      【業界背景】
      #{build_industry_context(genre_data, sub_data)}

      【EEAT強化情報】
      #{eeat_context}

      【追加指示】
      #{effective_prompt}
    PROMPT
  end

  # ==========================================================
  # 既出セクション要旨ブロック生成(既存と同一)
  # ==========================================================
  def self.build_covered_points_block(covered_points)
    return "" if covered_points.blank?

    lines = covered_points.map { |cp| "- #{cp[:title]}: #{cp[:gist]}" }

    <<~TEXT
      【既出セクションの要旨（重複禁止）】
      #{lines.join("\n")}
    TEXT
  end

  def self.extract_gist(section_body)
    GptGenerationLocale.extract_gist(section_body)
  end

  # ==========================================================
  # 【頻出フレーズ追跡】6文字以上の連続する語句(固有の言い回し)を
  # 抽出し、記事全体でのべ出現回数をカウントする。
  # 「開封データ・URLトラッキング」のような特徴的なフレーズが
  # セクションをまたいで繰り返し使われるのを検知するための仕組み。
  # ==========================================================
  def self.track_phrase_frequency!(phrase_counts, section_body)
    return if section_body.blank?

    chunks = section_body.scan(/[一-龠ぁ-んァ-ヶー・A-Za-z0-9]{6,}/)

    chunks.each do |chunk|
      # ごく短い助詞混じりの断片や、数字だけの塊はノイズになりやすいので除外
      next if chunk.match?(/\A[0-9]+\z/)

      phrase_counts[chunk] += 1
    end
  end

  # ==========================================================
  # 頻出フレーズ(2回以上使用済み)を、次のセクション生成時に
  # 「言い換えてください」という指示として渡すブロックを作る
  # ==========================================================
  def self.build_overused_phrases_block(phrase_counts)
    overused = phrase_counts.select { |_, count| count >= 2 }
                            .sort_by { |_, count| -count }
                            .first(10)
                            .map(&:first)

    return "" if overused.blank?

    <<~TEXT
      【表現の重複回避(厳守)】
      以下の語句・言い回しは、これまでのセクションで既に2回以上使われています。
      同じ言葉をそのまま繰り返さず、意味を保ったまま別の言葉・表現に言い換えてください。
      (例:同じ機能を指す場合でも、毎回同じ固有名詞的フレーズで説明しない)
      #{overused.map { |p| "- #{p}" }.join("\n")}
    TEXT
  end

  # ==========================================================
  # Markdown表の簡易バリデーション(既存と同一)
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
  # 業界コンテキスト生成(既存と同一)
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