require "net/http"
require "json"
require "openssl"
require "uri"

# ==========================================================
# 【汎用エッセイ生成版】既存の gpt_pillar_generator.rb と差し替えて使う版。
# クラス名・メソッド名は既存と同一なので、呼び出し側のコード
# (GenerateColumnBodyJob等)は変更不要。
#
# 前バージョンからの修正点(2026-08版):
#
# 1. 【数値・事実レベルの重複検出】
#    旧版は「6文字以上の連続文字列の完全一致」でしか重複を検出できず、
#    「クラスターも平均15個提案される」「平均15個提案されるクラスター」
#    のように、助詞や語順が変わるだけで同じ事実を繰り返しても
#    検出できなかった。数値+単位のパターンを抽出し、言い回しが
#    変わっても同じ事実の再掲を検出・禁止するようにした。
#
# 2. 【書き出しパターンの多様化】
#    旧版は「文末の問いかけ」しか監視しておらず、「夜更け」「夜の机で」
#    のように全セクションが同じ時間帯・情景描写から始まる
#    "逆テンプレ化"を検出できなかった。書き出しの型(時間帯描写など)を
#    トラッキングし、繰り返しを避けるよう明示的に指示するブロックを追加。
#
# 3. 【問いかけ終わりの検出範囲を拡張】
#    旧版は文末が「？」「?」で終わる場合のみカウントしていたため、
#    「〜だろうか。」「〜ではありませんか。」のような句点で終わる
#    疑問形が検出をすり抜けていた。正規表現でこれらの疑問形も
#    まとめて検出し、カウント対象を導入部・まとめも含めた記事全体に拡張。
#
# 4-補. 【書き出し検出の抜け穴を修正(2026-08 2回目)】
#    OPENING_MOTIF_WORDS が固定語句リストだったため、「夜」を避けても
#    「昼」に言い換えるだけで検出をすり抜けていた(実際に生成された記事で
#    7ブロック中6ブロックが「時間帯+情景描写」型を再生産していた)。
#    正規表現ベースの検出に変更し、まとめ(conclusion_prompt)にも
#    回避ブロックを配線し忘れていたのを修正。回避指示も「単語の言い換え」
#    ではなく「型そのものを変える」よう明示する文言に強化した。
#
# 4-補2. 【書き出し検出を単語ベースから文型ベースに変更(2026-08 3回目)】
#    正規表現でも「時間帯を表す単語」を列挙する方式だと、実際には
#    夜更け→昼→朝→夕方と単語だけをローテーションして型自体は
#    使い回す、という形で再発した(2026-08の生成で確認)。
#    単語を見るのをやめ、「短い場面描写+読点+私は」という文型そのものを
#    検出する方式に変更。時間帯に限らず、場所・天気・行動など
#    どんな場面描写を持ってきても検出できる。
#
# 5. 【SEO/コンテンツマーケ用語の直書きを解消】
#    article_type が "pillar"(SEO用語)に無条件で固定されていたのを、
#    既存値がある場合は上書きしない・デフォルト値も汎用語に変更。
#    見出し・本文プロンプト自体はもともとジャンル非依存な作りだったため、
#    今回の修正では「決め打ちのSEO用語」と「同一事実の使い回し」を
#    解消することに絞った(プロンプト文面自体の書き換えは最小限)。
# ==========================================================
class GptPillarNote
  class GenerationCancelledError < StandardError; end

  MODEL_NAME = "gpt-5.4-nano"
  GPT_API_URL = "https://api.openai.com/v1/chat/completions"

  CLAUDE_API_URL = "https://api.anthropic.com/v1/messages"
  CLAUDE_MODEL   = "claude-sonnet-4-6"

  # ----------------------------------------------------------
  # 【直書き設定】自社サービスのURL。差し替えれば別サービスの
  # 記事も同じ仕組みで作れる。
  # ----------------------------------------------------------
  OWN_SERVICE_URL  = "https://drafity.pro"
  OWN_SERVICE_NAME = "Drafity"

  # article_type のデフォルト値。旧版は "pillar"(SEO専用語)を
  # 無条件で入れていたが、この生成器はジャンルを問わず使うため
  # 汎用語に変更。既に値が入っている場合は上書きしない。
  DEFAULT_ARTICLE_TYPE = "essay"

  # 文末が疑問形として扱われるパターン(「？」以外の疑問形も含む)
  QUESTION_ENDING_PATTERN = /(？|\?|ませんか|でしょうか|だろうか|ないだろうか|と思いませんか|たくならないか|ではありませんか)[。.]?\s*\z/

  # 記事全体を通じて許容する「疑問形での終わり」の最大回数
  # (導入部・各見出し・まとめを合わせた総数でカウントする)
  MAX_QUESTION_ENDINGS = 2

  # 「〜、私は…」型(短い場面描写+読点+一人称)の開き方を、文型そのもので
  # 検出する。「夜」「昼」「朝」のような時間帯の単語だけを見ていると、
  # 単語を変えるだけで回避されてしまう(実際、2026-08の生成では
  # 夜更け→昼→朝→夕方と単語だけローテーションする形で再発した)ため、
  # 冒頭の短い場面描写+読点+「私は」という構造自体を判定する。
  OPENING_TEMPLATE_PATTERN = /\A([^。！？\n]{1,25})、\s*(私は|私も|私の|僕は|そして私は)/

  # 【書き出しの型を肯定形で指定する(2026-08 4回目)】
  # 「〜という書き方をするな」という否定形の指示は、gpt-5.4-nanoのような
  # 軽量モデルには効きにくく、実際に回避指示を出したセクションの
  # 8割で同じ「場面描写+私は」型が再発した(2026-08の生成で確認)。
  # 「今回はこの型で書け」という肯定形の指示に変え、セクションのindexに
  # 応じて機械的に型を割り当てる方式にした。情景描写(時間帯・場所などから
  # 入る型)は導入部だけで使い、以降のセクション・まとめでは使わせない。
  OPENING_TECHNIQUES = [
    {
      key: :dialogue,
      instruction: "会話・セリフ・心の中の声から書き始めてください。" \
        "例:誰かに言われた一言をそのまま引用する、自分がふと思った言葉を鉤括弧で示す、" \
        "といった形で最初の一文を作ってください。"
    },
    {
      key: :action,
      instruction: "具体的な行動・動作の描写から書き始めてください。" \
        "例:「〜を開いた。」「〜を眺めた。」のように、時間帯や場所の説明を挟まず、" \
        "動作そのものを最初の一文にしてください。"
    },
    {
      key: :contrast,
      instruction: "対比・逆接の構文から書き始めてください。" \
        "例:「〜ではなく、〜」「〜というより、〜」のような対比を最初の一文に使ってください。"
    },
    {
      key: :assertion,
      instruction: "強い断定の一文から書き始めてください。" \
        "例:状況説明を挟まず、「〜だ。」のように主張や気づきをそのまま最初の一文に置いてください。"
    },
    {
      key: :question,
      instruction: "問いかけの一文から書き始めてください。" \
        "例:「〜だろうか。」のような疑問文を最初の一文に使ってください" \
        "(この書き出しの疑問文は、文末の問いかけ回数のカウントには含めません)。"
    }
  ].freeze

  def self.opening_technique_for(index)
    OPENING_TECHNIQUES[index % OPENING_TECHNIQUES.length]
  end

  def self.build_opening_technique_block(technique)
    <<~TEXT
      【この段落の書き出し方(指定・厳守)】
      #{technique[:instruction]}
      「(時間帯や場所の情景描写)、私は〜」という型(例:「夜の机に向かうと、私は〜」
      「朝のコーヒーが冷める前に、私は〜」)は導入部で使い切っているため、
      このセクションでは使わないでください。
    TEXT
  end

  # ==========================================================
  # メイン生成ロジック
  # ==========================================================
  def self.generate_full_from_existing_column!(column)
    raise "タイトルが空です" if column.title.blank?
    ensure_not_cancelled!(column)

    client = column.client
    target_category = detect_category(column)
    current_genre   = column.genre.presence || GenreRegistry.from_ja(target_category) || "other"

    puts "▶ 統合生成開始(汎用版): #{column.title} (判定: #{target_category}, genre: #{current_genre})"

    genre_data = GenreRegistry.genre_entry(current_genre, client: client) || {}
    sub_key    = GenreRegistry.resolve_sub_category_key(column, current_genre, client: client)
    sub_data   = sub_key.present? ? genre_data.dig(:sub_categories, sub_key.to_sym) : nil

    # ----------------------------------------------------------
    # 自社事実の取得(web_fetchで直接取得。失敗しても記事は続行する)
    # ----------------------------------------------------------
    own_facts = fetch_web_facts_strict(OWN_SERVICE_URL)
    puts(own_facts.present? ? "✅ 自社事実の取得に成功" : "ℹ️ 自社事実は取得できず。サービス名のみで軽く触れる")

    effective_prompt = build_effective_prompt(column, own_facts)

    eeat_context = build_essay_context(column, genre_data, sub_data)

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
      res = generate_structure(column, target_category, genre_data, sub_data, eeat_context, effective_prompt)

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
      **(column.article_type.present? ? {} : { article_type: DEFAULT_ARTICLE_TYPE }),
      **(column.code.present? ? {} : { code: clean_code })
    )

    # ----------------------------------------------------------
    # 本文生成(目次なし)
    # ----------------------------------------------------------
    body_content = ""
    covered_points = []
    phrase_counts = Hash.new(0)        # 文字列レベルの頻出フレーズ追跡(旧版から継続)
    used_facts = []                    # 数値・事実レベルの既出トラッキング(新設)
    used_openings = []                 # 書き出しパターンの実績ログ(検出結果の記録用。指示には使わない)
    question_ending_total = 0          # 「疑問形終わり」の総回数(記事全体で共有・新設)

    # --- 導入部 ---
    # 導入部だけは情景描写からの書き出しを許可する(以降のセクションでは使わせない)
    ensure_not_cancelled!(column)
    intro_text = call_text_section(
      introduction_prompt(column, target_category, genre_data, sub_data, eeat_context, effective_prompt)
    )
    body_content += intro_text
    body_content += "\n\n"

    track_phrase_frequency!(phrase_counts, intro_text)
    track_facts!(used_facts, intro_text)
    track_opening!(used_openings, intro_text, expected_technique: nil)
    question_ending_total += 1 if question_like_ending?(intro_text)

    structure_data["structure"].each_with_index do |section, idx|
      ensure_not_cancelled!(column)
      h2_title = section["h2_title"]

      body_content += "## #{h2_title}\n\n"

      overused_block = build_overused_phrases_block(phrase_counts)
      used_facts_block = build_used_facts_block(used_facts)
      technique = opening_technique_for(idx)
      opening_instruction_block = build_opening_technique_block(technique)
      allow_question_ending = question_ending_total < MAX_QUESTION_ENDINGS

      section_body = call_text_section(
        h2_content_prompt(
          column, target_category, section, genre_data, sub_data, eeat_context,
          covered_points, effective_prompt, overused_block, used_facts_block,
          opening_instruction_block, allow_question_ending
        )
      )

      section_body.gsub!(/\A\s*#+\s+#{Regexp.escape(h2_title)}\s*\n+/i, "")
      section_body.gsub!(/\A\s*#{Regexp.escape(h2_title)}\s*\n+/i, "")

      body_content += section_body
      body_content += "\n\n"

      covered_points << { title: h2_title, gist: extract_gist(section_body) }
      track_phrase_frequency!(phrase_counts, section_body)
      track_facts!(used_facts, section_body)
      track_opening!(used_openings, section_body, expected_technique: technique)
      question_ending_total += 1 if question_like_ending?(section_body)

      sleep(1.2)
    end

    # --- まとめ ---
    ensure_not_cancelled!(column)
    used_facts_block = build_used_facts_block(used_facts)
    conclusion_technique = opening_technique_for(structure_data["structure"].length)
    opening_instruction_block = build_opening_technique_block(conclusion_technique)
    allow_question_ending = question_ending_total < MAX_QUESTION_ENDINGS

    conclusion_text = call_text_section(
      conclusion_prompt(
        column, target_category, genre_data, sub_data, eeat_context, covered_points,
        effective_prompt, used_facts_block, opening_instruction_block, allow_question_ending
      )
    )
    track_opening!(used_openings, conclusion_text, expected_technique: conclusion_technique)
    body_content += conclusion_text

    body_content += "\n\n{::options auto_ids=\"false\" /}"

    ensure_not_cancelled!(column)
    column.update!(body: body_content, status: "completed")

    begin
      FluxImageGeneratorService.generate!(column)
    rescue => e
      Rails.logger.error "[FluxImageGeneration] column #{column.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end

    puts "✅ 生成完了(汎用版): #{clean_code}"

    true
  end

  def self.ensure_not_cancelled!(column)
    return unless GenerateColumnBodyJob.cancelled?(column.id)

    raise GenerationCancelledError, "記事生成がユーザー操作で停止されました"
  end

  private

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
  # Claude APIレスポンスからテキスト部分だけを抽出
  # ==========================================================
  def self.extract_claude_text(res)
    return "" unless res

    res["content"].to_a.select { |c| c["type"] == "text" }.map { |c| c["text"] }.join("\n").strip
  end

  # ==========================================================
  # web_fetchで自社サービスのURLを直接取得する(検索は使わない)
  # ==========================================================
  def self.fetch_web_facts_strict(target_url)
    return nil if target_url.blank?

    domain = URI.parse(target_url).host rescue nil
    return nil if domain.blank?

    puts "🔎 Web直接取得(web_fetch)開始: #{target_url} (許可ドメイン: #{domain})"

    prompt = <<~PROMPT
      web_fetchツールを使って、次のURLのページ内容を直接取得してください。
      検索(web_search)は使わないでください。このURL以外のページは一切参照しないでください。

      取得対象URL: #{target_url}

      【出力条件】
      - 実際にこのURLから取得できた内容に基づく事実だけを、日本語の箇条書きで出力する
      - サービス内容、機能、料金、会社情報など
      - このURLの取得に失敗した場合、または内容が不十分な場合は、
        他の情報で埋め合わせず、「取得失敗」という1行だけを出力する
      - 「まず指定URLのページ内容を取得します」のような作業説明の前置きを一切書かない
      - 前置き・後書きは不要。箇条書き、または「取得失敗」の1行のみ出力する
    PROMPT

    res = call_claude_api(prompt, use_web_fetch: true, allowed_domains: [domain])
    return nil unless res

    facts = extract_claude_text(res)

    if facts.blank? || facts.include?("取得失敗") || facts.length < 30
      puts "⚠️ Web直接取得: 有効な事実が取得できませんでした"
      return nil
    end

    puts "✅ Web直接取得完了(#{facts.length}文字)"
    facts
  rescue => e
    puts "❌ fetch_web_facts_strict error: #{e.message}"
    nil
  end

  def self.call_claude_api(prompt, use_web_fetch: false, allowed_domains: nil)
    uri = URI(CLAUDE_API_URL)

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["x-api-key"] = ENV["ANTHROPIC_API_KEY"]
    req["anthropic-version"] = "2023-06-01"

    payload = {
      model: CLAUDE_MODEL,
      max_tokens: 1500,
      messages: [{ role: "user", content: prompt }]
    }

    if use_web_fetch
      tool = { type: "web_fetch_20250910", name: "web_fetch", max_uses: 3 }
      tool[:allowed_domains] = allowed_domains if allowed_domains.present?
      payload[:tools] = [tool]
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
  # column.prompt + 自社サービスの事実 を統合したプロンプトを作る
  # ==========================================================
  def self.build_effective_prompt(column, own_facts)
    parts = []
    parts << column.prompt if column.prompt.present?

    parts << "サービス名：#{OWN_SERVICE_NAME}(#{OWN_SERVICE_URL})"

    if own_facts.present?
      parts << <<~TEXT
        【#{OWN_SERVICE_NAME}のWeb直接取得による確認済み事実(この範囲内でのみ使用可)】
        #{own_facts}

        (注意: この事実の中の数値・機能名は、記事全体を通じて基本的に1回だけ触れれば十分。
        セクションごとに同じ数値を言い換えて繰り返さないこと。既に使った数値は
        後述の【既出の具体的数値】ブロックで随時知らされる)
      TEXT
    else
      parts << "【注意】具体的な事実は取得できていない。数値・機能名は創作せず、サービス名(#{OWN_SERVICE_NAME})に触れる程度に留める。"
    end

    parts.join("\n")
  end

  # ==========================================================
  # エッセイのトーン・背景情報
  # ==========================================================
  def self.build_essay_context(column, genre_data, sub_data)
    contexts = []

    contexts << "記事ジャンル: #{genre_data[:ja]}" if genre_data[:ja].present?

    if sub_data.present?
      contexts << "対象読者: #{sub_data[:target]}" if sub_data[:target].present?
      contexts << "業界説明: #{sub_data[:description]}" if sub_data[:description].present?
      contexts << "業界特徴(語りの材料として使ってよい): #{sub_data[:features].join('、')}" if sub_data[:features].present?
      contexts << "業界課題(自分の考えを語る切り口として使ってよい): #{sub_data[:industry_weakness]}" if sub_data[:industry_weakness].present?
    end

    contexts << <<~TEXT
      以下を重視して執筆すること:
      - 一人称(「私は」「〜と思う」「〜と感じた」)のエッセイ調で書く
      - 実務マニュアルのような硬い解説にしない
      - 個人の視点・経験・葛藤が伝わる書き方にする
      - 断定しすぎず、迷いや気づきのプロセスも書いてよい
      - 宣伝色は抑える。ただし記事全体を通じて最低1箇所は、
        【追加指示】に書かれたサービス名(#{OWN_SERVICE_NAME})に自然に触れること。
        固有名詞を一切出さないまま終わるのは禁止(何の話か読者に伝わらなくなるため)
      - 読者に語りかけるような、対話的なトーンにする
    TEXT

    contexts.join("\n")
  end

  # ==========================================================
  # 【文字列レベルの頻出フレーズ追跡】(旧版から継続。完全一致のみ検出)
  # ==========================================================
  def self.track_phrase_frequency!(phrase_counts, section_body)
    return if section_body.blank?

    chunks = section_body.scan(/[一-龠ぁ-んァ-ヶー・A-Za-z0-9]{6,}/)

    chunks.each do |chunk|
      next if chunk.match?(/\A[0-9]+\z/)
      phrase_counts[chunk] += 1
    end
  end

  def self.build_overused_phrases_block(phrase_counts)
    overused = phrase_counts.select { |_, count| count >= 2 }
                            .sort_by { |_, count| -count }
                            .first(10)
                            .map(&:first)

    return "" if overused.blank?

    <<~TEXT
      【表現の重複回避(厳守)】
      以下の語句・言い回しは、これまでのセクションで既に2回以上使われています。
      同じ言葉・似た構文をそのまま繰り返さず、意味を保ったまま別の言葉・言い回しに変えてください。
      (例:同じ問いかけの構文を毎回使わない。「あなたの〜ではありませんか？」のような
      定型的な呼びかけ文を繰り返さない)
      #{overused.map { |p| "- #{p}" }.join("\n")}
    TEXT
  end

  # ==========================================================
  # 【数値・事実レベルの重複追跡】(新設)
  # 「平均15個」「100点満点」のような数値+単位のパターンを抽出し、
  # 言い回しが変わっても同じ事実の再掲を検出できるようにする。
  # ==========================================================
  NUMERIC_FACT_PATTERN = /[0-9０-９]+(?:\.[0-9０-９]+)?\s*(?:点満点|点|個|回|%|％|件|円|分|時間|人|社|つ|倍|位|日間|日|週間|ヶ月|か月|年)/

  def self.extract_numeric_facts(text)
    return [] if text.blank?

    text.scan(NUMERIC_FACT_PATTERN).map { |f| normalize_fact(f) }
  end

  def self.normalize_fact(fact)
    fact.tr("０-９", "0-9").gsub(/\s+/, "")
  end

  def self.track_facts!(used_facts, text)
    used_facts.concat(extract_numeric_facts(text))
  end

  def self.build_used_facts_block(used_facts)
    return "" if used_facts.blank?

    <<~TEXT
      【既出の具体的数値(重複禁止・厳守)】
      以下の数値情報は、言い回しを変えたとしてもこれまでの本文で既に触れています。
      同じ数値をそのまま繰り返し出さないでください。新しい数値情報が特になければ、
      無理に数値に触れず、感覚・エピソードベースで書いてください。
      #{used_facts.uniq.map { |f| "- #{f}" }.join("\n")}
    TEXT
  end

  # ==========================================================
  # 【書き出しパターンの重複追跡】(新設)
  # 「夜更け」「夜の机で」のように、全セクションが同じ時間帯・
  # 情景描写から始まる"逆テンプレ化"を防ぐ。
  # ==========================================================
  def self.detect_opening_motif(text)
    return nil if text.blank?

    head = text.strip[0, 45].to_s
    match = head.match(OPENING_TEMPLATE_PATTERN)
    match && match[1]
  end

  def self.track_opening!(used_openings, text, expected_technique:)
    motif = detect_opening_motif(text)
    used_openings << motif if motif.present?

    return if motif.blank?

    # 診断ログ: 情景描写+私は型を指定していない(あるいは導入部以外の)セクションで
    # この型が再発していないかを記録する。生成は止めず、ログにだけ残す。
    if expected_technique.present?
      puts "⚠️ 書き出し型の指定違反の疑い(指定: #{expected_technique[:key]}): 「#{motif}、私は」型で開始されています"
    end
  end

  # ==========================================================
  # 【疑問形終わりの検出】(検出範囲を拡張・新設)
  # 「？」以外にも「だろうか」「ではありませんか」等の疑問形を検出する。
  # ==========================================================
  def self.question_like_ending?(text)
    return false if text.blank?

    text.strip.match?(QUESTION_ENDING_PATTERN)
  end

  # ==========================================================
  # Meta生成
  # ==========================================================
  def self.generate_meta_info(column, category, genre_data, sub_data, eeat_context, effective_prompt)
    prompt = <<~PROMPT
      以下の記事情報から、投稿用のメタ情報をJSON形式で生成してください。

      【記事タイトル】
      #{column.title}

      【ジャンル】
      #{category}

      【記事テーマ】
      #{effective_prompt}

      【重要】
      - descriptionは、記事の要約として使う1〜2文のキャプション
      - 硬いSEO説明文ではなく、読みたくなる一言にする
      - keywordは記事に関連するタグ候補を2〜4個、カンマ区切りで
      - codeは英語スラッグ
      - JSON以外禁止

      【ジャンル情報】
      #{build_industry_context(genre_data, sub_data)}

      【エッセイのトーン】
      #{eeat_context}

      出力形式:
      {
        "code": "english-slug",
        "description": "日本語のキャプション",
        "keyword": "タグ1, タグ2"
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
  # 構成生成(見出しは緩め、3〜5個)
  # ==========================================================
  def self.generate_structure(column, category, genre_data, sub_data, eeat_context, effective_prompt)
    prompt = <<~PROMPT
      以下のテーマで、エッセイ記事の見出し構成をJSON形式で生成してください。

      【記事タイトル】
      #{column.title}

      【ジャンル】
      #{category}

      【追加指示】
      #{effective_prompt}

      【記事方針】
      - この記事は一人称エッセイである
      - 実務解説記事のような硬い見出し構成にしない
      - 「なぜこれを書こうと思ったか」→「経験・気づき」→「今考えていること」のような、
        自然な思考の流れを作る見出しにする
      - 各見出しは、読者の興味を引く柔らかい言い回しにする(体言止めの実務見出しは避ける)
      - 各見出しは異なる話題・異なる気づきを扱うこと(同じ話の繰り返し禁止)

      【ジャンル背景】
      #{build_industry_context(genre_data, sub_data)}

      【エッセイのトーン】
      #{eeat_context}

      【出力条件】
      - 見出しは3〜5個(エッセイなので詰め込みすぎない)
      - 全て日本語
      - 見出しのみ
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
    uri = URI(GPT_API_URL)

    req = Net::HTTP::Post.new(uri)

    req["Content-Type"] = "application/json"
    req["Authorization"] = "Bearer #{ENV["GPT_API_KEY"]}"

    system_content = <<~SYSTEM
      あなたは人気のエッセイストです。

      【最重要ルール】
      - 日本語のみ
      - 一人称(「私は」「〜と思う」)のエッセイ調で書く
      - 実務マニュアル・SEO記事のような硬い解説文体は禁止
      - 「〜が重要です」「〜してください」のような指示・断定の連発は避ける
      - 個人の経験・気づき・迷いが伝わる文章にする
      - 宣伝色を抑える。ただし固有名詞(サービス名)を一切出さないまま終わるのは禁止
      - 箇条書き・表は基本的に使わない(文章で語る)
      - 「この記事では」「まとめると」のような機械的な前置き・締めを使わない
      - 他セクションで述べた話の繰り返し禁止(新しい気づき・視点を出すこと)
      - 同じ数値・統計を言い回しを変えて繰り返し出すことも禁止(既出の場合は触れない)

      【書き出しの多様化(厳守)】
      - 「夜」「朝」などの時間帯描写から始める書き出しを、毎回同じ型で使い回さない
      - セクションごとに違う入り方(会話、疑問、具体的な出来事、対比など)を試みる

      【文末表現の多様化(厳守)】
      - 読者への問いかけで終える手法は"時々使えるアクセント"であり、毎回使う型にしてはならない
      - 「？」を使わない疑問形の言い回し(「〜だろうか。」「〜ではありませんか。」等)も
        問いかけ終わりとして扱われるため、多用しない
      - 断定、具体的な情景描写、次への布石、静かな余韻など、問いかけ以外の終わり方を優先する
      - 「あなたの〜ではありませんか？」「〜と思いませんか？」のような定型的な呼びかけ構文を
        セクションごとに繰り返さない
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
        { role: "system", content: system_content },
        { role: "user", content: prompt }
      ],
      temperature: 0.6
    }

    payload[:response_format] = { type: "json_object" } if json_mode

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
  # 導入文
  # ==========================================================
  def self.introduction_prompt(column, category, genre_data, sub_data, eeat_context, effective_prompt)
    <<~PROMPT
      「#{column.title}」というテーマで記事の書き出しを作成してください。

      【条件】
      - 日本語
      - 400〜700文字
      - 「なぜこれを書こうと思ったか」「最近感じていること」から自然に始める
      - 一人称のエッセイ調
      - 見出し禁止
      - 実務解説の書き出し(「〜とは」から始まる定義文)は禁止
      - 読者の共感を誘う具体的なシーン・実感から入る(時間帯や場所の情景描写から入ってよいのは
        この導入部だけ。この型は後続のセクションでは使わせないため、ここで使い切ってよい)
      - 文末は問いかけ以外の形(断定・情景描写など)で終える(「だろうか」「ではありませんか」等の
        疑問形も含めて問いかけとして扱うので避けること)

      【ジャンル背景】
      #{build_industry_context(genre_data, sub_data)}

      【エッセイのトーン】
      #{eeat_context}

      【追加指示】
      #{effective_prompt}
    PROMPT
  end

  # ==========================================================
  # 見出しごとの本文
  # ==========================================================
  def self.h2_content_prompt(column, category, section, genre_data, sub_data, eeat_context, covered_points, effective_prompt, overused_block, used_facts_block, opening_instruction_block, allow_question_ending)
    ending_instruction =
      if allow_question_ending
        "最後の1文は、断定・情景描写・次への布石・問いかけのいずれかで締めてよい" \
        "(「？」を使わない「だろうか」「ではありませんか」等の疑問形も問いかけ扱いになるため、" \
        "問いかけ系の終わり方は記事全体で#{MAX_QUESTION_ENDINGS}回までに留めること)"
      else
        "この記事では既に問いかけ終わり(「？」「だろうか」「ではありませんか」等を含む)を" \
        "使い切っている。この見出しは断定・具体的な情景描写・次への布石のいずれかで締め、" \
        "疑問形の文末は一切使わないこと"
      end

    <<~PROMPT
      以下の見出しに続くエッセイの本文を執筆してください。

      【記事タイトル】
      #{column.title}

      【見出し】
      #{section["h2_title"]}

      #{build_covered_points_block(covered_points)}

      #{overused_block}

      #{used_facts_block}

      #{opening_instruction_block}

      【禁止ルール(厳守)】
      - 見出しの言葉をそのまま主語としてオウム返しする書き出しを禁止する
      - 上記【既出セクションの要旨】と同じ話の繰り返しを禁止する
      - 箇条書き・表を使わない
      - 実務解説調(「〜が重要です」「〜する必要があります」の連発)を禁止する

      【セクション末尾の書き方】
      #{ending_instruction}

      【条件】
      - 日本語
      - 300〜500文字
      - 一人称のエッセイ調
      - 具体的なエピソード・実感を交える
      - 宣伝色を抑えつつ、自然な範囲でサービス名や具体的な事実に触れてもよい
        (ただし既出の数値はそのまま繰り返さない)

      【ジャンル背景】
      #{build_industry_context(genre_data, sub_data)}

      【エッセイのトーン】
      #{eeat_context}

      【追加指示】
      #{effective_prompt}
    PROMPT
  end

  # ==========================================================
  # まとめ
  # ==========================================================
  def self.conclusion_prompt(column, category, genre_data, sub_data, eeat_context, covered_points, effective_prompt, used_facts_block, opening_instruction_block, allow_question_ending)
    ending_instruction =
      if allow_question_ending
        "文末が単なる問いかけだけで終わらないようにする(問いかけを使う場合も、断定や余韻を添えて締める。" \
        "「だろうか」「ではありませんか」等の疑問形も問いかけとして扱う)"
      else
        "この記事では既に問いかけ終わりを使い切っている。断定・情景描写・余韻のいずれかで締め、" \
        "疑問形の文末(「？」「だろうか」「ではありませんか」等)は一切使わないこと"
      end

    <<~PROMPT
      「#{column.title}」の記事の締めくくりを執筆してください。

      #{build_covered_points_block(covered_points)}

      #{used_facts_block}

      #{opening_instruction_block}

      【条件】
      - 見出しは付けない(自然な最後の段落として書く)
      - 日本語
      - 250〜400文字
      - 「まとめると」のような機械的な要約から始めない
      - 記事全体を振り返りつつ、今後への思いで締める
      - 宣伝色を抑える
      - 上記【既出セクションの要旨】を踏まえ、同じ話の繰り返しにしない
      - この記事のどこかでサービス名に触れていない場合は、ここで自然に触れること
        (ただし既出の数値はそのまま繰り返さない)
      - #{ending_instruction}

      【ジャンル背景】
      #{build_industry_context(genre_data, sub_data)}

      【エッセイのトーン】
      #{eeat_context}

      【追加指示】
      #{effective_prompt}
    PROMPT
  end

  # ==========================================================
  # 既出セクション要旨ブロック生成
  # ==========================================================
  def self.build_covered_points_block(covered_points)
    return "" if covered_points.blank?

    lines = covered_points.map { |cp| "- #{cp[:title]}: #{cp[:gist]}" }

    <<~TEXT
      【既出セクションの要旨(重複禁止)】
      #{lines.join("\n")}
    TEXT
  end

  def self.extract_gist(section_body)
    return "" if section_body.blank?

    sentences = section_body.split(/(?<=。)/).map(&:strip).reject(&:blank?)
    sentences.last(2).join("").truncate(180)
  end

  # ==========================================================
  # ジャンルコンテキスト生成
  # ==========================================================
  def self.build_industry_context(genre_data, sub_data)
    texts = []

    if genre_data.present?
      texts << "ジャンル: #{genre_data[:ja]}" if genre_data[:ja].present?

      if genre_data[:keywords].present?
        texts << "関連キーワード: #{genre_data[:keywords].join('、')}"
      end
    end

    if sub_data.present?
      texts << "対象: #{sub_data[:target]}" if sub_data[:target].present?
      texts << "ジャンル説明: #{sub_data[:description]}" if sub_data[:description].present?

      if sub_data[:features].present?
        texts << "特徴: #{sub_data[:features].join('、')}"
      end

      if sub_data[:industry_weakness].present?
        texts << "課題: #{sub_data[:industry_weakness]}"
      end
    end

    texts.join("\n")
  end
end