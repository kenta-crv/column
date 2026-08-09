require "net/http"
require "json"
require "openssl"
require "uri"

# ==========================================================
# 【Qiita向けアレンジ版】gpt_pillar_generator.rb のQiita用調整版。
# クラス名・公開メソッド名は既存と同一なので、呼び出し側のコード
# (GenerateColumnBodyJob等)は変更不要。
#
# 元の「エッセイ生成版」との主な違い(2026-08 Qiita調整版):
#
# 1. 【文体をエッセイ調→技術記事調に変更】
#    一人称の語り口自体は残しつつ(体験ベースの導入・気づきは書いてよい)、
#    「実務マニュアル文体を避ける」という制約を緩め、技術的な正確さ・
#    再現性のある説明を優先するよう指示を変更した。
#
# 2. 【箇条書き・表・コードブロックの解禁】
#    旧版(エッセイ版)は「箇条書き・表は基本的に使わない」だったが、
#    Qiitaでは手順・比較・コード例の提示に箇条書き/表/コードブロックが
#    必須級のため、積極的に使ってよい方針に変更。ただし「架空のAPI・
#    ライブラリ・関数名・ベンチマーク数値の捏造禁止」を新たに明記した。
#
# 3. 【メタ情報のkeywordをQiitaタグ向けに変更】
#    旧版はSEOキーワード想定の文言だったが、Qiitaのタグ慣習
#    (言語名・フレームワーク名・技術要素名を短く付ける)に合わせて
#    プロンプトを調整した。
#
# 4. 【プラットフォーム依存の後処理を削除】
#    本文末尾に付与していた `{::options auto_ids="false" /}` は
#    Kramdown(旧プラットフォームのMarkdownレンダラ)固有の記法で
#    Qiitaでは意味を持たないため削除した。
#
# 5. 【重複回避ロジックは維持】
#    数値・事実レベルの重複検出、書き出しパターンの多様化、
#    疑問形終わりの検出/上限管理は、技術記事でも「同じ数値を
#    セクションごとに言い換えて繰り返す」「毎セクション同じ書き出し
#    構文になる」といった問題は起こり得るため、そのまま維持している。
#
# 実際の生成結果をレビューして判明した不具合の修正(2026-08 Qiita版 2回目):
#
# 6. 【サービス名の言及が記事全体で6回に膨らむバグを修正】
#    「記事全体で最低1箇所は触れること」という指示を、eeat_context
#    (全セクション共通の静的コンテキスト)に埋め込んでいたため、
#    各セクション生成が互いの結果を知らないまま独立にこの指示を満たそうとし、
#    結果的に記事全体で6回もサービス名+URLが登場する事態が発生した。
#    実際に生成された本文中の言及回数を数値・書き出しパターンと同様に
#    トラッキングし(count_service_mentions/track済みcount)、
#    MAX_SERVICE_NAME_MENTIONS(=2)に達したら以降のセクションでは
#    言及禁止、逆にまとめの時点で0回なら必須、という動的な指示
#    (build_service_mention_block)に置き換えた。また本文中に生のURLを
#    書かせず、URLは生成後にRuby側で記事末尾に必ず1回だけ機械的に
#    付与する方式にし、URLの重複を構造的に防いでいる。
#
# 7. 【まとめ(conclusion)にフレーズ重複検出が効いていなかったバグを修正】
#    build_overused_phrases_block(phrase_counts)は導入部・各見出しの
#    生成では使われていたが、conclusion_promptの呼び出し時にだけ
#    このブロックが一切生成・渡されていなかった(実装漏れ)。そのため
#    「運用の再現性」のような抽象的な言い回しが導入部で使われても、
#    まとめの生成時にはそれを警告する情報が渡らず、同じ表現がまとめで
#    再利用される問題が起きていた。conclusion_promptにoverused_block
#    引数を追加し、他セクションと同じ仕組みで重複警告を渡すようにした。
#    あわせて、重複警告の閾値も「2回以上で警告」(=警告が出る時点で
#    既に2回目の使用が発生済み)から「1回でも既出なら警告」に変更し、
#    2回目の使用が起きる前に検出できるようにした。
#
# 8. 【疑問形終わりが連続するセクションで発生するのを防止】
#    旧版はMAX_QUESTION_ENDINGS(記事全体で2回まで)という上限管理は
#    あったが、「隣接するセクションが連続して疑問形で終わる」ケースは
#    防げなかった(上限の2回を使い切るタイミングが偶然隣接しても許容
#    されてしまう)。直前のセクションが疑問形で終わっていた場合は、
#    たとえ記事全体の上限に余裕があっても次のセクションでは疑問形終わりを
#    禁止するよう、previous_ended_with_questionフラグを追加した。
#
# 9. 【GPTシステムプロンプトに残っていた矛盾ルールを削除】
#    call_gpt_apiのsystem_content(全API呼び出し共通)に
#    「固有名詞(サービス名)を一切出さないまま終わるのは禁止」という
#    静的な指示が残っており、これがユーザープロンプト側の動的な
#    service_mention_block(言及上限に達したら禁止、という指示)と
#    矛盾していた。システムプロンプト側は「個別の指示に従う」という
#    中立的な文言に変更し、言及可否の判断を完全にservice_mention_block
#    側に委ねるようにした。
# ==========================================================
class GptPillarQiita
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

  # article_type のデフォルト値。Qiita向けのため技術記事を示す
  # 汎用語に変更。既に値が入っている場合は上書きしない。
  DEFAULT_ARTICLE_TYPE = "tech_article"

  # 文末が疑問形として扱われるパターン(「？」以外の疑問形も含む)
  QUESTION_ENDING_PATTERN = /(？|\?|ませんか|でしょうか|だろうか|ないだろうか|と思いませんか|たくならないか|ではありませんか)[。.]?\s*\z/

  # 記事全体を通じて許容する「疑問形での終わり」の最大回数
  # (導入部・各見出し・まとめを合わせた総数でカウントする)
  MAX_QUESTION_ENDINGS = 2

  # 記事全体を通じて許容する「サービス名(#{OWN_SERVICE_NAME})への言及」の最大回数。
  # 旧版は「最低1箇所は触れること」という指示を全セクション共通で
  # 静的に渡していたため、各セクションが独立にこの指示を満たそうとして
  # 記事全体で何度も(実例では6回)言及される事態が発生した。
  # 実際に生成された本文を数えながら動的に上限管理する方式に変更する。
  MAX_SERVICE_NAME_MENTIONS = 2

  # 「〜、私は…」型(短い場面描写+読点+一人称)の開き方を、文型そのもので
  # 検出する。単語(時間帯など)だけを見ていると言い換えで回避されるため、
  # 冒頭の短い場面描写+読点+「私は」という構造自体を判定する。
  OPENING_TEMPLATE_PATTERN = /\A([^。！？\n]{1,25})、\s*(私は|私も|私の|僕は|そして私は)/

  # 【書き出しの型を肯定形で指定する】
  # 「〜という書き方をするな」という否定形の指示は軽量モデルには効きにくいため、
  # 「今回はこの型で書け」という肯定形の指示に変え、セクションのindexに
  # 応じて機械的に型を割り当てる。技術記事向けに例を調整している。
  OPENING_TECHNIQUES = [
    {
      key: :dialogue,
      instruction: "同僚や自分自身が発した一言、あるいはエラーメッセージ・ログの引用から" \
        "書き始めてください。例:実際に見た/言われた一言をそのまま最初の一文に置く、" \
        "エラー文言や状況を端的に示す一文から入る、といった形にしてください。"
    },
    {
      key: :action,
      instruction: "具体的な操作・実装・検証の描写から書き始めてください。" \
        "例:「〜を実行した。」「〜の設定を変更した。」のように、背景説明を挟まず、" \
        "行動そのものを最初の一文にしてください。"
    },
    {
      key: :contrast,
      instruction: "Before/Afterや旧手法との対比構文から書き始めてください。" \
        "例:「〜ではなく、〜」「これまでは〜だったが、〜」のような対比を最初の一文に使ってください。"
    },
    {
      key: :assertion,
      instruction: "結論を先に一文で言い切る書き出しにしてください(結論ファースト)。" \
        "例:状況説明を挟まず、「〜だ。」のように結論や気づきをそのまま最初の一文に置いてください。"
    },
    {
      key: :question,
      instruction: "読者が抱きがちな疑問・つまずきを一文で提示する書き出しにしてください。" \
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
      「(状況・場面描写)、私は〜」という型(例:「深夜の障害対応で、私は〜」
      「レビューで指摘を受けて、私は〜」)は導入部で使い切っているため、
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

    puts "▶ 統合生成開始(Qiita版): #{column.title} (判定: #{target_category}, genre: #{current_genre})"

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

    # 見出しにサービス名が紛れ込んでいないかの安全網。
    # プロンプトで禁止しても、モデルが指示に従わずh2_titleに
    # サービス名を含めるケースがあったため(実例で確認)、機械的に除去する。
    structure_data["structure"].each do |section|
      section["h2_title"] = sanitize_heading_of_service_name(section["h2_title"])
    end

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
    phrase_counts = Hash.new(0)        # 文字列レベルの頻出フレーズ追跡
    used_facts = []                    # 数値・事実レベルの既出トラッキング
    used_openings = []                 # 書き出しパターンの実績ログ(検出結果の記録用。指示には使わない)
    question_ending_total = 0          # 「疑問形終わり」の総回数(記事全体で共有)
    previous_ended_with_question = false # 直前セクションが疑問形で終わったか(連続を防ぐため)
    service_mention_count = 0          # サービス名の言及回数(記事全体で共有・新設)

    # --- 導入部 ---
    # 導入部だけは背景・状況描写からの書き出しを許可する(以降のセクションでは使わせない)
    ensure_not_cancelled!(column)
    service_mention_block = build_service_mention_block(service_mention_count)
    intro_text = call_text_section(
      introduction_prompt(column, target_category, genre_data, sub_data, eeat_context, effective_prompt, service_mention_block)
    )
    strip_stray_headings!(intro_text)
    body_content += intro_text
    body_content += "\n\n"

    track_phrase_frequency!(phrase_counts, intro_text)
    track_facts!(used_facts, intro_text)
    track_opening!(used_openings, intro_text, expected_technique: nil)
    question_ending_total += 1 if question_like_ending?(intro_text)
    previous_ended_with_question = question_like_ending?(intro_text)
    service_mention_count += count_service_mentions(intro_text)

    structure_data["structure"].each_with_index do |section, idx|
      ensure_not_cancelled!(column)
      h2_title = section["h2_title"]

      body_content += "## #{h2_title}\n\n"

      overused_block = build_overused_phrases_block(phrase_counts)
      used_facts_block = build_used_facts_block(used_facts)
      technique = opening_technique_for(idx)
      opening_instruction_block = build_opening_technique_block(technique)
      # 記事全体の上限内でも、直前のセクションが疑問形で終わっていた場合は
      # このセクションでは疑問形終わりを使わせない(連続発生を防ぐ)
      allow_question_ending = question_ending_total < MAX_QUESTION_ENDINGS && !previous_ended_with_question
      service_mention_block = build_service_mention_block(service_mention_count)

      section_body = call_text_section(
        h2_content_prompt(
          column, target_category, section, genre_data, sub_data, eeat_context,
          covered_points, effective_prompt, overused_block, used_facts_block,
          opening_instruction_block, allow_question_ending, service_mention_block
        )
      )

      section_body.gsub!(/\A\s*#+\s+#{Regexp.escape(h2_title)}\s*\n+/i, "")
      section_body.gsub!(/\A\s*#{Regexp.escape(h2_title)}\s*\n+/i, "")
      # Zenn版のレビューで見つかった「セクション内に##サブ見出しが混入する」
      # 事象への対処。Qiita版でも同じプロンプト設計を使っているため同様に発生しうる。
      strip_stray_headings!(section_body)

      body_content += section_body
      body_content += "\n\n"

      covered_points << { title: h2_title, gist: extract_gist(section_body) }
      track_phrase_frequency!(phrase_counts, section_body)
      track_facts!(used_facts, section_body)
      track_opening!(used_openings, section_body, expected_technique: technique)
      question_ending_total += 1 if question_like_ending?(section_body)
      previous_ended_with_question = question_like_ending?(section_body)
      service_mention_count += count_service_mentions(section_body)

      sleep(1.2)
    end

    # --- まとめ ---
    ensure_not_cancelled!(column)
    # 旧版はここでoverused_blockを一切生成・受け渡ししておらず、
    # フレーズ重複検出がまとめにだけ効かない実装漏れがあった
    # (「運用の再現性」等が導入部とまとめで気づかれず再利用された原因)。
    # 他セクションと同様に計算して渡すよう修正。
    overused_block = build_overused_phrases_block(phrase_counts)
    used_facts_block = build_used_facts_block(used_facts)
    conclusion_technique = opening_technique_for(structure_data["structure"].length)
    opening_instruction_block = build_opening_technique_block(conclusion_technique)
    allow_question_ending = question_ending_total < MAX_QUESTION_ENDINGS && !previous_ended_with_question
    # まとめの時点でサービス名に一度も触れていなければ、ここで必須にする
    # (安全網。ここまでの各セクションは「上限に達していなければ触れてよい」
    # だけなので、たまたま誰も触れないまま終わるケースに対応する)
    force_mention = service_mention_count.zero?
    service_mention_block = build_service_mention_block(service_mention_count, force_mention: force_mention)

    conclusion_text = call_text_section(
      conclusion_prompt(
        column, target_category, genre_data, sub_data, eeat_context, covered_points,
        effective_prompt, overused_block, used_facts_block, opening_instruction_block,
        allow_question_ending, service_mention_block
      )
    )
    strip_stray_headings!(conclusion_text)
    track_opening!(used_openings, conclusion_text, expected_technique: conclusion_technique)
    service_mention_count += count_service_mentions(conclusion_text)
    body_content += conclusion_text

    # 本文中の言及回数によらず、クリック可能なURLは記事末尾に必ず1回だけ
    # システム側で付与する(本文中に生のURLを書かせない代わりの担保。
    # プロンプト側で model に伝えている「URLは末尾に1回自動付与される」
    # という約束をここで実装として満たす)。
    #
    # 旧版は「Drafity: https://drafity.pro」という無機質な label:value 形式で、
    # 直前までの一人称の語りと文体が食い違い、機械的に貼り付けたことが
    # 一目でわかってしまう書式だった(実際のレビューで指摘あり)。
    # Qiitaの記事でよくある「参考」フッター的な体裁(Markdownリンク+
    # 軽い一言)に変更し、本文の流れから浮かないようにする。
    body_content += "\n\n---\n参考: [#{OWN_SERVICE_NAME}](#{OWN_SERVICE_URL})"

    ensure_not_cancelled!(column)
    column.update!(body: body_content, status: "completed")

    begin
      FluxImageGeneratorService.generate!(column)
    rescue => e
      Rails.logger.error "[FluxImageGeneration] column #{column.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end

    puts "✅ 生成完了(Qiita版): #{clean_code}"

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
      - サービス内容、機能、料金、技術スタック、対応言語/フレームワークなど
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

    parts << <<~TEXT
      サービス名：#{OWN_SERVICE_NAME}
      (注意: 本文中に生のURL文字列(https://...)を書かないこと。
      URLはシステム側で記事末尾に1回だけ自動的に付与するため、
      本文内でリンクや完全なURLを書く必要はない。サービス名に触れる場合は
      名前のみで十分。言及してよい回数の上限は、セクションごとに別途
      【サービス名の言及について】ブロックで知らされる)
    TEXT

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
  # 技術記事のトーン・背景情報(Qiita向け)
  # ==========================================================
  def self.build_essay_context(column, genre_data, sub_data)
    contexts = []

    contexts << "記事ジャンル: #{genre_data[:ja]}" if genre_data[:ja].present?

    if sub_data.present?
      contexts << "対象読者: #{sub_data[:target]}" if sub_data[:target].present?
      contexts << "業界説明: #{sub_data[:description]}" if sub_data[:description].present?
      contexts << "業界特徴(語りの材料として使ってよい): #{sub_data[:features].join('、')}" if sub_data[:features].present?
      contexts << "業界課題(切り口として使ってよい): #{sub_data[:industry_weakness]}" if sub_data[:industry_weakness].present?
    end

    contexts << <<~TEXT
      以下を重視して執筆すること(Qiita向け技術記事):
      - 一人称(「私は」「〜と思う」「〜と感じた」)の語り口は使ってよいが、
        技術的な正確さ・再現性のある説明を最優先する
      - 手順・比較・コード例を示す際は、箇条書き・表・コードブロックを積極的に使ってよい
      - コードを書く場合は、実際に動作確認したことがあるかのような正確さで書き、
        言語を明示したコードブロック(```language ... ```)で示す。
        存在しないAPI・ライブラリ・関数名や、根拠のないベンチマーク数値を捏造しない
      - 個人の経験・気づき・試行錯誤のプロセスを書いてよいが、最終的には
        読者が実務で使える情報(手順・原因・対策・トレードオフ)に着地させる
      - 断定しすぎず、迷いや検証過程も書いてよいが、事実と推測は区別して書く
      - 宣伝色は抑える。サービス名への言及可否・回数は各セクションのプロンプトで
        個別に指示されるので、その指示に従うこと(ここでは一律に「触れること」を
        強制しない)
      - 読者に語りかけるような、対話的なトーンにする
    TEXT

    contexts.join("\n")
  end

  # ==========================================================
  # 【文字列レベルの頻出フレーズ追跡】(完全一致のみ検出)
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
    # 閾値をcount>=2からcount>=1に厳格化。
    # 旧版は「2回以上使われた語句」を警告対象にしていたため、警告が出る
    # 時点で既に2回目の使用が発生済みだった(=手遅れ)。実例では
    # 「運用の再現性」が導入部で1回使われた段階では警告対象にならず、
    # まとめでの再使用を防げなかった。1回でも既出なら次のセクションで
    # 警告するよう変更し、2回目が起きる前に検出できるようにする。
    overused = phrase_counts.select { |_, count| count >= 1 }
                            .sort_by { |_, count| -count }
                            .first(15)
                            .map(&:first)

    return "" if overused.blank?

    <<~TEXT
      【表現の重複回避(厳守)】
      以下の語句・言い回しは、これまでのセクションで既に使われています。
      同じ言葉・似た構文をそのまま繰り返さず、意味を保ったまま別の言葉・言い回しに変えてください。
      (例:同じ問いかけの構文を毎回使わない。「あなたの〜ではありませんか？」のような
      定型的な呼びかけ文を繰り返さない。「運用の再現性」のような抽象的なフレーズを
      導入部とまとめで使い回さない)
      #{overused.map { |p| "- #{p}" }.join("\n")}
    TEXT
  end

  # ==========================================================
  # 【数値・事実レベルの重複追跡】
  # 「平均15個」「100点満点」のような数値+単位のパターンを抽出し、
  # 言い回しが変わっても同じ事実の再掲を検出できるようにする。
  # ==========================================================
  NUMERIC_FACT_PATTERN = /[0-9０-９]+(?:\.[0-9０-９]+)?\s*(?:点満点|点|個|回|%|％|件|円|分|時間|人|社|つ|倍|位|日間|日|週間|ヶ月|か月|年|ms|MB|GB|行)/

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
      無理に数値に触れず、手順・原因・対策ベースで書いてください。
      #{used_facts.uniq.map { |f| "- #{f}" }.join("\n")}
    TEXT
  end

  # ==========================================================
  # 【サービス名の言及回数トラッキング】(新設)
  # 旧版は「記事全体で最低1箇所は触れること」という指示を全セクションの
  # プロンプトに毎回静的に埋め込んでいたため、各セクションが独立に
  # この指示を満たそうとして、記事全体で何度も(実例では6回)言及される
  # 事態が起きていた。実際に生成された本文中の言及回数を数え、
  # 上限に達したら以降のセクションでは言及しないよう動的に指示する。
  # ==========================================================
  def self.count_service_mentions(text)
    return 0 if text.blank?

    text.scan(OWN_SERVICE_NAME).length
  end

  # 見出し(h2_title)は generate_structure という別のAPI呼び出しで生成され、
  # そちらにはサービス名の言及上限の仕組み(service_mention_count等)が
  # 一切伝わっていない。プロンプトで「見出しに含めるな」と指示しても
  # 従われないケースがあったため(実例で「Drafityで〜する手順」という
  # 見出しが生成された)、機械的に除去する安全網を用意する。
  def self.sanitize_heading_of_service_name(title)
    return title if title.blank?
    return title unless title.include?(OWN_SERVICE_NAME)

    puts "⚠️ 見出しにサービス名が含まれていたため除去: 「#{title}」"

    cleaned = title.dup
    # 「Drafityで」「Drafityの」のような助詞付きパターンをまとめて除去
    cleaned.gsub!(/#{Regexp.escape(OWN_SERVICE_NAME)}(で|の|を|に|と|から|による|のような)?/, "")
    cleaned.gsub!(/\A[、,・\s]+/, "")   # 除去した結果、先頭に残った読点等だけを取り除く
    cleaned.gsub!(/[、,]{2,}/, "、")    # 除去の結果連続してしまった読点を1つにまとめる
    cleaned.strip!
    cleaned = "実践して分かったこと" if cleaned.blank?
    cleaned
  end

  def self.build_service_mention_block(mention_count, force_mention: false)
    if mention_count >= MAX_SERVICE_NAME_MENTIONS
      <<~TEXT
        【サービス名の言及について(厳守)】
        #{OWN_SERVICE_NAME}は、この記事内で既に#{mention_count}回言及されています。
        このセクションでは新たにサービス名を出さず、内容そのもの(手順・原因・対策)に
        集中してください。URLも書かないでください。
      TEXT
    elsif force_mention
      <<~TEXT
        【サービス名の言及について(必須)】
        この記事ではまだ#{OWN_SERVICE_NAME}という名前に一度も触れていません。
        このセクションで、自然な文脈で1回だけ触れてください
        (URLは書かず、名前のみで十分です)。
      TEXT
    else
      <<~TEXT
        【サービス名の言及について】
        #{OWN_SERVICE_NAME}に触れてもよい残り回数は#{MAX_SERVICE_NAME_MENTIONS - mention_count}回です。
        無理に毎セクション触れる必要はありません。触れる場合も名前のみで十分で、
        URLは書かないでください。
      TEXT
    end
  end

  # ==========================================================
  # 【書き出しパターンの重複追跡】
  # 全セクションが同じ場面描写から始まる"逆テンプレ化"を防ぐ。
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

    # 診断ログ: 指定した技法と違う型が再発していないかを記録する。生成は止めず、ログにだけ残す。
    if expected_technique.present?
      puts "⚠️ 書き出し型の指定違反の疑い(指定: #{expected_technique[:key]}): 「#{motif}、私は」型で開始されています"
    end
  end

  # ==========================================================
  # 【疑問形終わりの検出】
  # 「？」以外にも「だろうか」「ではありませんか」等の疑問形を検出する。
  # ==========================================================
  def self.question_like_ending?(text)
    return false if text.blank?

    text.strip.match?(QUESTION_ENDING_PATTERN)
  end

  # ==========================================================
  # Meta生成(Qiitaのタグ慣習に合わせてkeywordの指示を調整)
  # ==========================================================
  def self.generate_meta_info(column, category, genre_data, sub_data, eeat_context, effective_prompt)
    prompt = <<~PROMPT
      以下の記事情報から、Qiita投稿用のメタ情報をJSON形式で生成してください。

      【記事タイトル】
      #{column.title}

      【ジャンル】
      #{category}

      【記事テーマ】
      #{effective_prompt}

      【重要】
      - descriptionは、記事の要約として使う1〜2文のキャプション
      - 硬いSEO説明文ではなく、読みたくなる一言にする
      - keywordは、Qiitaのタグとして自然な技術用語(言語名・フレームワーク名・
        ツール名・技術要素名など)を2〜4個、カンマ区切りで。
        マーケティング的な抽象語句(例:「効率化」「時短」単体など)は避け、
        具体的な技術名を優先すること
      - codeは英語スラッグ
      - JSON以外禁止

      【ジャンル情報】
      #{build_industry_context(genre_data, sub_data)}

      【記事のトーン】
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
      以下のテーマで、Qiita向け技術記事の見出し構成をJSON形式で生成してください。

      【記事タイトル】
      #{column.title}

      【ジャンル】
      #{category}

      【追加指示】
      #{effective_prompt}

      【記事方針】
      - 一人称の語り口を交えてよいが、読者が実務で使える情報に着地させる技術記事である
      - 「背景・課題」→「試したこと・実装」→「わかったこと・今後の展望」のような、
        自然な思考の流れを作る見出しにする
      - 各見出しは、内容が一目でわかる具体的な言い回しにする
      - 各見出しは異なる話題・異なる気づきを扱うこと(同じ話の繰り返し禁止)
      - 見出し(h2_title)にサービス名(#{OWN_SERVICE_NAME})を含めないこと。
        サービス名への言及は本文中でのみ、別途上限回数の指示に従って行う。
        見出しはあくまで扱う話題(手順・比較・落とし穴など)を表す言い回しにする

      【ジャンル背景】
      #{build_industry_context(genre_data, sub_data)}

      【記事のトーン】
      #{eeat_context}

      【出力条件】
      - 見出しは3〜5個(詰め込みすぎない)
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

  # プロンプトで「本文中に新しい見出しを追加しない」と指示しても、
  # モデルが##等の見出し行を挿入するケースがあったため(Zenn版のレビューで、
  # 1セクション内に複数の##サブ見出しが混入し、記事全体の見出し階層が
  # 崩れる事象を確認)、機械的に太字へ変換する安全網を用意する。
  # 情報の区切りとしての意図は残しつつ、見出し階層(目次やアウトライン)
  # には影響しなくなる。
  #
  # 正規表現中の "#" はRubyの文字列/正規表現リテラルで#{...}による
  # 式展開のトリガーとして解釈されてしまうため、\#{1,6} のように
  # エスケープしてリテラルな#の1〜6回繰り返しとして扱わせている。
  def self.strip_stray_headings!(text)
    return text if text.blank?

    text.gsub!(/^\#{1,6}[ \t]+(.+)$/) { "**#{$1.strip}**" }
    text
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
      あなたはQiitaで人気のテックライター/エンジニアです。

      【最重要ルール】
      - 日本語のみ
      - 一人称(「私は」「〜と思う」)の語り口を使ってよいが、技術的な正確さを最優先する
      - 「〜が重要です」「〜してください」のような指示・断定の連発は避ける
      - 個人の経験・気づき・試行錯誤が伝わる文章にしつつ、最終的には
        読者が実務で使える情報(手順・原因・対策・トレードオフ)に着地させる
      - 宣伝色を抑える。固有名詞(サービス名)への言及可否・回数は、
        セクションごとのプロンプトで個別に渡される指示に厳密に従うこと
        (このシステムプロンプトの時点では、必ず触れる/触れないのどちらも強制しない)
      - 手順・比較・コード例には箇条書き・表・コードブロックを積極的に使ってよい
      - コード例を書く場合は、実在しないAPI・ライブラリ・関数名や、根拠のない
        ベンチマーク数値を捏造しない。コードブロックには言語を明示する(```ruby 等)
      - 「この記事では」「まとめると」のような機械的な前置き・締めを使わない
      - 他セクションで述べた話の繰り返し禁止(新しい気づき・視点を出すこと)
      - 同じ数値・統計を言い回しを変えて繰り返し出すことも禁止(既出の場合は触れない)

      【書き出しの多様化(厳守)】
      - 同じ場面描写の型を毎回使い回さない
      - セクションごとに違う入り方(引用、疑問、具体的な操作描写、対比、結論ファーストなど)を試みる

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
  def self.introduction_prompt(column, category, genre_data, sub_data, eeat_context, effective_prompt, service_mention_block)
    <<~PROMPT
      「#{column.title}」というテーマで記事の書き出しを作成してください。

      #{service_mention_block}

      【条件】
      - 日本語
      - 400〜700文字
      - 「なぜこの技術・課題に取り組むことになったか」「背景にある課題感」から自然に始める
      - 一人称の語り口を使ってよい
      - 見出し禁止
      - 辞書的な定義文(「〜とは」からいきなり始まる)は避け、具体的な状況・課題から入る
      - 文末は問いかけ以外の形(断定・状況描写など)で終える(「だろうか」「ではありませんか」等の
        疑問形も含めて問いかけとして扱うので避けること)

      【ジャンル背景】
      #{build_industry_context(genre_data, sub_data)}

      【記事のトーン】
      #{eeat_context}

      【追加指示】
      #{effective_prompt}
    PROMPT
  end

  # ==========================================================
  # 見出しごとの本文
  # ==========================================================
  def self.h2_content_prompt(column, category, section, genre_data, sub_data, eeat_context, covered_points, effective_prompt, overused_block, used_facts_block, opening_instruction_block, allow_question_ending, service_mention_block)
    ending_instruction =
      if allow_question_ending
        "最後の1文は、断定・状況描写・次への布石・問いかけのいずれかで締めてよい" \
        "(「？」を使わない「だろうか」「ではありませんか」等の疑問形も問いかけ扱いになるため、" \
        "問いかけ系の終わり方は記事全体で#{MAX_QUESTION_ENDINGS}回までに留めること)"
      else
        "この記事では既に問いかけ終わり(「？」「だろうか」「ではありませんか」等を含む)を" \
        "使い切っている。この見出しは断定・具体的な状況描写・次への布石のいずれかで締め、" \
        "疑問形の文末は一切使わないこと"
      end

    <<~PROMPT
      以下の見出しに続く技術記事の本文を執筆してください。

      【記事タイトル】
      #{column.title}

      【見出し】
      #{section["h2_title"]}

      #{build_covered_points_block(covered_points)}

      #{overused_block}

      #{used_facts_block}

      #{opening_instruction_block}

      #{service_mention_block}

      【禁止ルール(厳守)】
      - 見出しの言葉をそのまま主語としてオウム返しする書き出しを禁止する
      - 上記【既出セクションの要旨】と同じ話の繰り返しを禁止する
      - 実在しないAPI・ライブラリ・関数名・コマンド、根拠のないベンチマーク数値を捏造しない
      - 「〜が重要です」「〜する必要があります」のような指示・断定の連発を禁止する
      - このセクションの中に##等の新しい見出し行を追加しない。話題を分けたい場合は
        見出しではなく、太字(**〜**)や箇条書きの先頭ラベルで表現すること。
        この見出し(#{section["h2_title"]})の直下は、1つの連続した文章
        (箇条書き・表・コードブロックは可)として書き、独立した節に分割しない

      【セクション末尾の書き方】
      #{ending_instruction}

      【条件】
      - 日本語
      - 300〜500文字
      - 一人称の語り口を交えてよいが、技術的な正確さを最優先する
      - 手順・比較・コード例を示す場合は、箇条書き・表・コードブロック(言語明示)を使ってよい
      - 具体的なエピソード・実感を交えてもよい
      - サービス名への言及可否・回数は上記【サービス名の言及について】の指示に厳密に従うこと
        (ただし既出の数値はそのまま繰り返さない)

      【ジャンル背景】
      #{build_industry_context(genre_data, sub_data)}

      【記事のトーン】
      #{eeat_context}

      【追加指示】
      #{effective_prompt}
    PROMPT
  end

  # ==========================================================
  # まとめ
  # ==========================================================
  def self.conclusion_prompt(column, category, genre_data, sub_data, eeat_context, covered_points, effective_prompt, overused_block, used_facts_block, opening_instruction_block, allow_question_ending, service_mention_block)
    ending_instruction =
      if allow_question_ending
        "文末が単なる問いかけだけで終わらないようにする(問いかけを使う場合も、断定や余韻を添えて締める。" \
        "「だろうか」「ではありませんか」等の疑問形も問いかけとして扱う)"
      else
        "この記事では既に問いかけ終わりを使い切っている(または直前のセクションが問いかけ終わりだった)。" \
        "断定・状況描写・余韻のいずれかで締め、疑問形の文末(「？」「だろうか」「ではありませんか」等)は" \
        "一切使わないこと"
      end

    <<~PROMPT
      「#{column.title}」の記事の締めくくりを執筆してください。

      #{build_covered_points_block(covered_points)}

      #{overused_block}

      #{used_facts_block}

      #{opening_instruction_block}

      #{service_mention_block}

      【条件】
      - 見出しは付けない(自然な最後の段落として書く)
      - 日本語
      - 250〜400文字
      - 「まとめると」のような機械的な要約から始めない
      - 記事全体を振り返りつつ、今後試したいこと・次のステップで締める
      - 宣伝色を抑える
      - 上記【既出セクションの要旨】と【表現の重複回避】を踏まえ、導入部で使った言い回しを
        そのまま繰り返さない(例:導入部の結びの一文を、まとめでほぼ同じ表現で使い回さない)
      - サービス名への言及可否は上記【サービス名の言及について】の指示に厳密に従うこと
        (ただし既出の数値はそのまま繰り返さない)
      - #{ending_instruction}

      【ジャンル背景】
      #{build_industry_context(genre_data, sub_data)}

      【記事のトーン】
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