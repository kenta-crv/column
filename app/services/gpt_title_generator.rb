require "net/http"
require "json"
require "openssl"

class GptTitleGenerator
  MODEL_NAME = "gpt-4o-mini"
  GPT_API_URL = "https://api.openai.com/v1/chat/completions"
  MAX_INTENT_SLOTS = 10

  def self.generate_titles(pillar_column, limit: nil)
    unless pillar_column&.title.present?
      Rails.logger.error("GptTitleGenerator: 親記事のタイトルが空です")
      return []
    end

    count = resolve_count(pillar_column, limit)
    return [] if count <= 0

    prompt = build_titles_prompt(
      pillar_column,
      count: count,
      existing_titles: existing_child_titles(pillar_column),
      sibling_pillar_titles: sibling_pillar_titles(pillar_column)
    )

    res = GptGenerationLocale.with_language(pillar_column) { call_gpt_api(prompt) }
    return [] if res.nil?

    begin
      json_content = JSON.parse(res.dig("choices", 0, "message", "content"))
      plans = Array(json_content["cluster_titles"])
      drop_overlapping_titles(plans, pillar_column).first(count)
    rescue => e
      Rails.logger.error("GptTitleGenerator: タイトルパースエラー: #{e.message}")
      []
    end
  end

  def self.resolve_count(pillar_column, limit)
    requested = limit.nil? ? MAX_INTENT_SLOTS : limit.to_i
    requested = [requested, MAX_INTENT_SLOTS].min
    [requested, 0].max
  end

  def self.build_titles_prompt(pillar_column, count:, existing_titles:, sibling_pillar_titles:)
    target_category = detect_category(pillar_column)
    service_info = GenreRegistry.service_profile(target_category)
    parent_terms = extract_title_elements(pillar_column.title)
    existing_titles_text = Array(existing_titles).reject(&:blank?).presence&.join("\n") || "（なし）"
    sibling_text = Array(sibling_pillar_titles).reject(&:blank?).presence&.join("\n") || "（なし）"

    <<~PROMPT
      # あなたの役割
      あなたはトピッククラスターの設計者です。
      親記事（ピラー）を補完する子記事タイトルを作ります。親の言い換えや、同じ検索意図の量産は禁止です。

      # 親記事
      - 親タイトル: #{pillar_column.title}
      - 業種カテゴリ: #{target_category}
      - 専門サービス強み: #{service_info}
      - 親タイトルに含まれる語（子で並べ替えて使い回さない）: #{parent_terms.join('、')}

      # 既存の子記事タイトル（同じ意図を繰り返さない）
      #{existing_titles_text}

      # 同じジャンルの他ピラー（これらの主題を奪わない）
      #{sibling_text}

      # 設計手順
      1. 親タイトルがすでに答えている中心クエリを把握する。
      2. この親の下でのみ成立する、互いに検索意図が異なる切り口を最大#{count}個決める。
         切り口は親の主題から導く。業種の固定リストを無理に当てはめない。
         親の文脈で実際に検索されるものだけを使う。例は一例であり必須ではない
         （原因、比較、手順、費用、対象別、リスク、導入 など）。
      3. 切り口ごとにタイトルを1つだけ作る。切り口が#{count}個に満たなければ、無理に埋めず少ない件数で返す。

      # 厳守
      1. 親タイトルの語順入れ替え・同義語置換・「完全ガイド／徹底解説」を足しただけの子は禁止。
      2. 見た目が違ってもクエリが同じものは1本にする。
         悪い例: 「失敗しない選び方」と「選定5つのポイント」と「チェックリスト」。
      3. 既存子記事・他ピラーと実質同じ需要のタイトルは出さない。
      4. 各タイトルは、その切り口だけで検索したくなる具体性を持つ。
      5. 件数は#{count}件以内。

      # 出力形式
      JSON形式のみ。解説やマークダウンは不要。
      {
        "cluster_titles": [
          { "intent": "短い切り口名", "title": "タイトル案" }
        ]
      }
    PROMPT
  end

  def self.existing_child_titles(pillar_column)
    return [] unless pillar_column.respond_to?(:id) && pillar_column.id.present?

    Column.where(parent_id: pillar_column.id).where.not(title: [nil, ""]).limit(80).pluck(:title)
  end

  def self.sibling_pillar_titles(pillar_column)
    return [] unless pillar_column.respond_to?(:genre)

    scope = Column.where(article_type: "pillar").where.not(title: [nil, ""])
    scope = scope.where(genre: pillar_column.genre) if pillar_column.genre.present?
    scope = scope.where.not(id: pillar_column.id) if pillar_column.id.present?
    if pillar_column.respond_to?(:client_id)
      scope = scope.where(client_id: pillar_column.client_id)
    end
    scope.limit(30).pluck(:title)
  end

  def self.drop_overlapping_titles(plans, pillar_column)
    blocked = (
      existing_child_titles(pillar_column) +
      [pillar_column.title] +
      sibling_pillar_titles(pillar_column)
    ).map { |title| normalize_title(title) }.reject(&:blank?)

    kept = []
    Array(plans).each do |plan|
      next unless plan.is_a?(Hash)

      title = plan["title"].to_s.strip
      next if title.blank?

      key = normalize_title(title)
      next if key.blank?
      next if blocked.any? { |other| titles_overlap?(key, other) }
      next if kept.any? { |prev| titles_overlap?(key, normalize_title(prev["title"])) }

      kept << plan
      blocked << key
    end
    kept
  end

  def self.titles_overlap?(a, b)
    return false if a.blank? || b.blank?
    return true if a == b
    return true if a.include?(b) || b.include?(a)

    prefix = a.chars.zip(b.chars).take_while { |x, y| x == y }.size
    prefix >= 14
  end

  def self.normalize_title(title)
    title.to_s.downcase.gsub(/[\s　\[\]【】「」『』（）()：:・\-_|！!？?]/, "")
  end

  private

  def self.detect_category(column)
    search_text = "#{column.title} #{column.keyword} #{column.genre} #{column.choice}"
    GenreRegistry::GENRES.each do |key, data|
      keywords = Array(data[:keywords])
      if keywords.any? { |w| search_text.include?(w) }
        return data[:ja]
      end
    end
    "その他"
  end

  def self.extract_title_elements(title)
    return [] if title.blank?

    cleaned = title.gsub(/[？\?！\!。、：:・「」『』【】（）()|\/]/, " ")
    words = cleaned.split(/[\s　]+/)
    words.select { |w| w.length >= 2 }.uniq
  end

  def self.call_gpt_api(prompt)
    prompt = GptGenerationLocale.prepare_user_prompt(prompt)
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
      temperature: 0.4
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
        nil
      end
    rescue => e
      Rails.logger.error("GptTitleGenerator: API通信エラー: #{e.message}")
      nil
    end
  end
end
