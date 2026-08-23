require "net/http"
require "json"
require "openssl"

class GptTitleGenerator
  MODEL_NAME = "gpt-4o-mini"
  GPT_API_URL = "https://api.openai.com/v1/chat/completions"
  MIN_TITLES = 15
  MAX_TITLES = 25

  def self.last_error
    Thread.current[:gpt_title_generator_error]
  end

  def self.generate_titles(pillar_column, limit: nil)
    remember_error!(nil)
    unless pillar_column&.title.present?
      Rails.logger.error("GptTitleGenerator: 親記事のタイトルが空です")
      remember_error!("親記事のタイトルが空です")
      return []
    end

    res = GptGenerationLocale.with_language(pillar_column) do
      call_gpt_api(build_titles_prompt(pillar_column))
    end
    return [] if res.nil?

    begin
      json_content = JSON.parse(res.dig("choices", 0, "message", "content"))
      plans = Array(json_content["cluster_titles"])
      cap = limit.nil? ? plans.size : [[limit.to_i, 0].max, plans.size].min
      plans.first(cap)
    rescue => e
      Rails.logger.error("GptTitleGenerator: タイトルパースエラー: #{e.message}")
      remember_error!("子タイトルの応答を解析できませんでした")
      []
    end
  end

  def self.build_titles_prompt(pillar_column)
    if english_prompt?(pillar_column)
      build_titles_prompt_en(pillar_column)
    else
      build_titles_prompt_ja(pillar_column)
    end
  end

  def self.english_prompt?(pillar_column)
    Column.english_language?(pillar_column.try(:language)) || GptGenerationLocale.english?
  end

  def self.build_titles_prompt_ja(pillar_column)
    category_key = detect_category_key(pillar_column)
    target_category = category_label(category_key, locale: :ja)
    service_info = GenreRegistry.service_profile(category_key)

    existing_titles = existing_child_titles(pillar_column)
    existing_titles_text = existing_titles.present? ? existing_titles.join("\n") : "（なし）"
    extracted_elements = extract_title_elements(pillar_column.title)

    <<~PROMPT
      # あなたの役割
      あなたは高度なSEO戦略家およびコンテンツ構造設計者です。
      与えられた親記事（ピラーページ）を、読者が抱く一連の疑問・関心を体系的にカバーする
      「トピッククラスター（子記事）タイトル群」に分解してください。
      単に親タイトルを言い換えたバリエーションを作る仕事ではありません。

      # 対象となる親記事（Pillar）データ
      - 親タイトル: #{pillar_column.title}
      - 業種カテゴリ: #{target_category}
      - 専門サービス強み: #{service_info}
      - 抽出された構成要素: #{extracted_elements.join(', ')}

      # 作業手順（出力前に必ずこの順で内部的に思考すること。思考過程自体は出力しない）

      ## STEP1: 親タイトルの型を分類する
      親タイトルを、以下のいずれかの「型」に分類する（複数該当する場合は最も強いものを主軸にする）。
      - 課題解決型（〜不足、〜対策、〜の悩み、〜を改善する 等）
      - 比較検討型（〜おすすめ、〜比較、〜どっちがいい 等）
      - ランキング/リスト型（〜選、〜一覧 等）
      - ハウツー型（〜のやり方、〜の始め方、〜入門 等）
      - 網羅解説型/用語解説型（〜とは、〜完全ガイド、〜まとめ 等）
      同時に、以下も特定する。
      - テーマ（何についての話か）
      - 主語・対象（誰の/何の課題・関心か）
      これらは子記事タイトル全体を貫く「一貫性の軸」であり、子記事はここから絶対に逸脱してはならない。

      ## STEP2: 型に応じて切り口（ファセット）を選定する
      以下は切り口の候補メニューであり、全部を使う必要はない。
      STEP1で分類した型に照らして「実際にこのテーマで成立する切り口」だけを選ぶこと。
      型に合わない切り口を無理に当てはめることは禁止する。
      逆にメニューになくてもテーマに強く関連する切り口があれば追加してよい。

      - 原因・背景（なぜその問題/状況が起きているか）※主に課題解決型
      - 解決策・具体的アプローチ（どう対処するか、手法や施策）※主に課題解決型
      - 対象・属性別の切り口（誰向けか、どんな属性・シーン特有の課題か）※ほぼ全型で有効
      - コスト・投資面 ※課題解決型・比較検討型・ハウツー型
      - 運用・定着・継続面（導入後の運用や継続にまつわる課題）※課題解決型・ハウツー型
      - 比較・選定基準（選択肢の比較、判断軸）※主に比較検討型・ランキング型
      - 事例・データ（具体的な成功/失敗パターン、数字）※ほぼ全型で有効
      - 将来性・トレンド ※課題解決型・網羅解説型
      - 制度・ツール・仕組み（活用できる公的制度やサービス、手法）※課題解決型・ハウツー型
      - リスク・注意点 ※課題解決型・比較検討型・ハウツー型
      - 手順・ステップ別 ※主にハウツー型
      - 選定基準の深掘り（価格/条件/対応エリア等の個別軸）※主に比較検討型・ランキング型
      - 用語・概念の個別解説 ※主に網羅解説型

      選んだ切り口同士は内容が重複しない「独立した論点」になるようにする。

      ## STEP3: 切り口ごとにタイトルを立てる
      STEP2で選んだ切り口それぞれについて1本ずつタイトルを作成する（同一切り口から2本以上は禁止）。
      1つの切り口に偏らせず、クラスター全体で親テーマの全体像を立体的に補完するよう
      バランスよく配分する（合計15〜25本）。

      同一の切り口、または内容が実質的に重なる切り口から2本以上生成することを禁止する。
      特に「方法」「手順」「実践」「基礎知識」「進め方」といった抽象語だけで
      差別化しようとするタイトルは、切り口が実質的に同じであるとみなし、クラスター全体で1本のみ許可する。
      親タイトルに含まれる語（例：「完全ガイド」「基礎知識」など親タイトルの主要ワードそのもの）を
      そのまま子タイトルの主語・骨格として流用することを禁止する。
      「比較」を切り口とするタイトルも、対象（業者/プラン/サービス等）や判断軸が異なる場合を除き1本のみとする。
      「〜な方法とその効果」「〜な手法とその効果」のように、切り口の名称は違っても
      文の構造（手段＋その結果・効果を並べるだけの形）が同じタイトルを2本以上作ることを禁止する。
      同じ構造になりそうな場合は、片方を「手順の詳細解説」、もう片方を「異なる方法論同士の比較」など
      役割が明確に異なる形に書き分けること。

      # 記事選定の条件（厳守）
      1. 【最重要】親タイトルの「型・方向性・ニュアンス」への完全な同調:
         STEP1で分類した型やテーマから外れるタイトルの生成を禁止する。

      2. 言い換え・類似生成の禁止:
         親タイトルや既存タイトルの単なる同義語・表現違いのバリエーション
         （実質的に同じ内容を別の言葉で言い直しただけのもの）は不可とする。
         各タイトルは、STEP2で立てた切り口に基づく「異なる論点」を扱っていなければならない。

      3. 構成要素の掛け合わせ:
         「抽出された構成要素」を適切にサンプリングして掛け合わせ、
         その親記事の文脈でしか成立しない具体的なタイトルにする。
         業種カテゴリ名だけに依存した、どのシーンでも使い回せる汎用タイトルは禁止する。

      4. 重複の禁止と類似の許可:
         既に存在する以下の子記事タイトルと内容が完全に被らないこと。
         ただしPillarの枝葉となるため、異なる切り口でのアプローチは許可する。
         [既存のタイトル一覧]
         #{existing_titles_text}

      5. 階層性とドメインの整合性:
         必ず「#{target_category}」のドメインに関連した範囲内で、
         かつ親タイトルの目的や提供価値から一切乖離しないこと。

      # 出力形式
      JSON形式のみで回答してください。余計な文字列（```json などのマークダウンやバッククォート）や解説のテキストは一切含めないでください。
      STEP1〜STEP3の思考過程は出力に含めず、最終的なタイトルのみを出力してください。
      {
        "cluster_titles": [
          { "title": "タイトル案", "angle": "採用した切り口（例：原因分析、コスト面など）" }
        ]
      }
    PROMPT
  end

  def self.build_titles_prompt_en(pillar_column)
    category_key = detect_category_key(pillar_column)
    target_category = category_label(category_key, locale: :en)
    service_info = GenreRegistry.service_profile(category_key)

    existing_titles = existing_child_titles(pillar_column)
    existing_titles_text = existing_titles.present? ? existing_titles.join("\n") : "(none)"
    extracted_elements = extract_title_elements(pillar_column.title)

    <<~PROMPT
      # Your role
      You are a senior SEO strategist and content architecture designer.
      Break the given parent article (pillar page) into a set of topic-cluster (child article) titles
      that systematically cover the questions and interests readers will have.
      Do not merely create paraphrased variations of the parent title.

      # Parent (Pillar) data
      - Parent title: #{pillar_column.title}
      - Industry category: #{target_category}
      - Service strengths: #{service_info}
      - Extracted title elements: #{extracted_elements.join(', ')}

      Genre / service facts above may be in Japanese. Treat them as source facts and express titles in English.
      Do not mix Japanese into the title strings.

      # Workflow (think through this order internally before outputting; do not output the reasoning)

      ## STEP1: Classify the parent title type
      Classify the parent title into one of the following types (if multiple apply, use the strongest as the primary axis).
      - Problem-solving (shortage, countermeasures, pain points, how to improve, etc.)
      - Comparison / evaluation (best, vs, which to choose, etc.)
      - Ranking / list (top N, roundup, directory, etc.)
      - How-to (how to do X, getting started, beginner guide, etc.)
      - Comprehensive / definition (what is X, complete guide, overview, etc.)
      Also identify:
      - Theme (what the article is about)
      - Subject / audience (whose problem or interest)
      These are the consistency axis across all child titles. Child titles must never drift from them.

      ## STEP2: Select angles (facets) that fit the type
      The list below is a candidate menu; you do not need to use all of them.
      Choose only angles that actually work for this theme given the STEP1 type.
      Do not force-fit angles that clash with the type.
      You may add strongly relevant angles even if they are not on the menu.

      - Causes / background (why the problem or situation exists) — mainly problem-solving
      - Solutions / concrete approaches (how to address it, methods, tactics) — mainly problem-solving
      - Audience / attribute angles (who it is for; scene-specific issues) — useful for almost all types
      - Cost / investment — problem-solving, comparison, how-to
      - Operations / adoption / continuity (post-launch operations and sticking with it) — problem-solving, how-to
      - Comparison / selection criteria (comparing options, decision axes) — mainly comparison, ranking
      - Case studies / data (success/failure patterns, numbers) — useful for almost all types
      - Outlook / trends — problem-solving, comprehensive
      - Programs / tools / systems (public programs, services, frameworks you can use) — problem-solving, how-to
      - Risks / caveats — problem-solving, comparison, how-to
      - Step-by-step process — mainly how-to
      - Deeper selection criteria (price, terms, coverage area, etc.) — mainly comparison, ranking
      - Term / concept explainers — mainly comprehensive / definition

      Selected angles must be independent topics that do not overlap in substance.

      ## STEP3: Write one title per angle
      Create exactly one title for each angle chosen in STEP2 (two or more from the same angle is forbidden).
      Do not over-index on one angle; balance the cluster so it complements the parent theme in 3D
      (15–25 titles total).

      Do not generate two or more titles from the same angle, or from angles that substantially overlap.
      Titles that only differentiate with abstract words like "method", "steps", "in practice",
      "fundamentals", or "how to proceed" count as the same angle — allow only one such title in the cluster.
      Do not reuse major parent-title words (e.g. "complete guide", "fundamentals") as the subject or
      backbone of a child title.
      Comparison-angle titles are limited to one unless the comparison target (vendor/plan/service, etc.)
      or decision axis clearly differs.
      Do not create two or more titles that share the same sentence structure even if the angle names differ
      (e.g. "X method and its effects" vs "Y approach and its effects" — means + outcome only).
      If structures would collide, rewrite so roles clearly differ — e.g. one as a detailed process explainer,
      another as a comparison of distinct methodologies.

      # Selection rules (strict)
      1. [Most important] Full alignment with the parent title's type, direction, and nuance:
         Do not generate titles that leave the STEP1 type or theme.

      2. No paraphrase / near-duplicate generation:
         Synonym swaps or reworded variations of the parent or existing titles
         (same substance in different wording) are not allowed.
         Each title must cover a distinct argument grounded in a STEP2 angle.

      3. Combine extracted elements:
         Sample and combine the "extracted title elements" so each title only makes sense
         in this parent article's context.
         Generic titles that only depend on the industry category name are forbidden.

      4. No exact overlap; similar-but-different angles allowed:
         Do not fully overlap existing child titles below.
         Because these are pillar branches, different-angle approaches are allowed.
         [Existing titles]
         #{existing_titles_text}

      5. Hierarchy and domain fit:
         Stay within the "#{target_category}" domain,
         and never drift from the parent title's purpose or value proposition.

      # Output format
      Reply with JSON only. Do not include markdown fences (```json), backticks, or explanatory text.
      Do not include STEP1–STEP3 reasoning — final titles only.
      All title and angle strings must be in English.
      {
        "cluster_titles": [
          { "title": "Title idea", "angle": "Chosen angle (e.g. root-cause analysis, cost)" }
        ]
      }
    PROMPT
  end

  def self.existing_child_titles(pillar_column)
    return [] unless pillar_column.respond_to?(:id) && pillar_column.id.present?

    Column.where(parent_id: pillar_column.id).pluck(:title)
  end

  private

  def self.detect_category_key(column)
    search_text = "#{column.title} #{column.keyword} #{column.genre} #{column.choice}"
    GenreRegistry::GENRES.each do |key, data|
      keywords = Array(data[:keywords])
      return key.to_s if keywords.any? { |w| search_text.include?(w) }
    end
    nil
  end

  def self.category_label(category_key, locale: :ja)
    if category_key.blank?
      return locale.to_s == "en" ? "Other" : "その他"
    end

    label = GenreRegistry.label_for(category_key, locale: locale).presence
    label ||= locale.to_s == "en" ? GenreRegistry.to_en(category_key) : GenreRegistry.to_ja(category_key)
    label.presence || (locale.to_s == "en" ? "Other" : "その他")
  end

  def self.detect_category(column, locale: :ja)
    category_label(detect_category_key(column), locale: locale)
  end

  def self.extract_title_elements(title)
    return [] if title.blank?

    cleaned = title.gsub(/[？\?！\!。、：:・「」『』【】（）()|\/]/, " ")
    words = cleaned.split(/[\s　]+/)
    words.select { |w| w.length >= 2 }.uniq
  end

  def self.call_gpt_api(prompt)
    # 英語記事は build_titles_prompt_en を使うため、日本語ラップは不要
    prompt = GptGenerationLocale.prepare_user_prompt(prompt) unless GptGenerationLocale.english?
    uri = URI(GPT_API_URL)
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["Authorization"] = "Bearer #{ENV['GPT_API_KEY']}"

    payload = {
      model: MODEL_NAME,
      messages: [
        { role: "system", content: GptGenerationLocale.resolve_title_system_prompt("あなたはSEOコンサルタントです。指定されたJSONフォーマットのオブジェクトのみを返却してください。マークダウンの枠組みやバッククォート、解説のテキストは一切不要です。") },
        { role: "user", content: prompt }
      ],
      response_format: { type: "json_object" },
      temperature: 0.6
    }
    req.body = payload.to_json

    begin
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 120) do |http|
        http.request(req)
      end

      if res.is_a?(Net::HTTPSuccess)
        JSON.parse(res.body)
      else
        Rails.logger.error("GptTitleGenerator: APIエラー #{res.code} #{res.body}")
        remember_error!(user_facing_api_error(res.code, res.body))
        nil
      end
    rescue => e
      Rails.logger.error("GptTitleGenerator: API通信エラー: #{e.message}")
      remember_error!("OpenAIへの通信に失敗しました")
      nil
    end
  end

  def self.remember_error!(message)
    Thread.current[:gpt_title_generator_error] = message.presence
  end

  def self.user_facing_api_error(code, body)
    parsed = JSON.parse(body.to_s) rescue nil
    api_code = parsed.is_a?(Hash) ? parsed.dig("error", "code").to_s : ""
    api_type = parsed.is_a?(Hash) ? parsed.dig("error", "type").to_s : ""

    if api_code == "credit_balance_exhausted" || api_type == "insufficient_quota"
      return "OpenAIのAPIクレジットが不足しています。課金設定を確認してください。"
    end
    if code.to_s == "429"
      return "OpenAIの利用上限に達しています。しばらく待ってから再試行してください。"
    end

    "子タイトルの生成に失敗しました（OpenAI HTTP #{code}）"
  end
end
