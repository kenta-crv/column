require "net/http"
require "json"

class SubCategorySuggestionService
  MODEL_NAME = "gpt-4o-mini"
  GPT_API_URL = "https://api.openai.com/v1/chat/completions"
  DEFAULT_SUGGESTION_COUNT = 5
  MAX_SUGGESTION_COUNT = 10
  MIN_SUGGESTION_COUNT = 1

  def self.call(key:, ja: nil, service_name: nil, strong_points: nil, keywords: nil, suggestion_count: nil)
    if key.blank?
      return { success: false, error: "ジャンルキーを入力してください", sub_categories: [] }
    end

    if strong_points.blank? && ja.blank? && service_name.blank?
      return { success: false, error: "訴求ポイントまたは表示名・サービス名のいずれかを入力してください", sub_categories: [] }
    end

    count = normalize_suggestion_count(suggestion_count)
    keyword_list = normalize_keywords(keywords)

    prompt = <<~PROMPT
      # あなたの役割
      あなたはBtoB/BtoCサービスのマーケティング戦略家です。
      大分類ジャンルの情報から、記事作成・SEOに使える「中分類（サブカテゴリ）」を#{count}件提案してください。

      # 大分類の情報
      - ジャンルキー: #{key}
      - 表示名: #{ja.presence || "（未入力）"}
      - サービス名: #{service_name.presence || "（未入力）"}
      - 訴求ポイント:
      #{strong_points.presence || "（未入力）"}
      - キーワード: #{keyword_list.presence || "（未入力）"}

      # 中分類の設計方針
      1. サービス内容・ターゲット・提供形態の違いで、重複の少ない#{count}件に分割すること
      2. 各中分類は記事の sub_genre として使われるため、検索意図の異なる切り口にすること
      3. key は英小文字・数字・アンダースコアのみ（例: daily_standard, office_cleaning）
      4. name は日本語の名称（必須）
      5. target / description / features / keywords は記事生成AIへの指示文として具体的に書くこと
      6. features と keywords はそれぞれ3〜5件の配列にすること
      7. price_hint と area は日本語で簡潔に（不明なら「要お見積り」「全国対応」など）
      8. strengths と industry_weakness は訴求ポイントを反映した差別化文にすること

      # 出力形式
      JSON形式のみで回答してください。余計な文字列は一切含めないでください。
      sub_categories 配列には必ず #{count} 件を含めてください。
      {
        "sub_categories": [
          {
            "key": "example_key",
            "name": "中分類名",
            "target": "ターゲット",
            "description": "サービス説明",
            "features": ["特徴1", "特徴2"],
            "keywords": ["キーワード1", "キーワード2"],
            "price_hint": "料金目安",
            "area": "対応エリア",
            "strengths": "強み",
            "industry_weakness": "業界課題と差別化"
          }
        ]
      }
    PROMPT

    res = call_gpt_api(prompt)
    return { success: false, error: "API通信エラーが発生しました", sub_categories: [] } if res.nil?

    begin
      json_content = JSON.parse(res.dig("choices", 0, "message", "content"))
      items = Array(json_content["sub_categories"]).map { |item| normalize_item(item) }.reject { |item| item[:key].blank? || item[:name].blank? }
      if items.empty?
        { success: false, error: "中分類の解析に失敗しました", sub_categories: [] }
      else
        { success: true, sub_categories: items }
      end
    rescue => e
      Rails.logger.error("SubCategorySuggestionService: パースエラー: #{e.message}")
      { success: false, error: "中分類の解析に失敗しました", sub_categories: [] }
    end
  end

  def self.normalize_suggestion_count(value)
    count = value.to_i
    count = DEFAULT_SUGGESTION_COUNT if count <= 0
    [[count, MIN_SUGGESTION_COUNT].max, MAX_SUGGESTION_COUNT].min
  end

  def self.normalize_keywords(keywords)
    case keywords
    when Array
      keywords.map(&:to_s).map(&:strip).reject(&:blank?).join("、")
    else
      keywords.to_s.split(/[\n,、]/).map(&:strip).reject(&:blank?).join("、")
    end
  end

  def self.normalize_item(item)
    item = item.with_indifferent_access
    {
      key: item[:key].to_s.strip.downcase,
      name: item[:name].to_s.strip,
      target: item[:target].to_s.strip,
      description: item[:description].to_s.strip,
      features_text: Array(item[:features]).map(&:to_s).map(&:strip).reject(&:blank?).join("\n"),
      keywords_text: Array(item[:keywords]).map(&:to_s).map(&:strip).reject(&:blank?).join("\n"),
      price_hint: item[:price_hint].to_s.strip,
      area: item[:area].to_s.strip,
      strengths: item[:strengths].to_s.strip,
      industry_weakness: item[:industry_weakness].to_s.strip
    }
  end

  private_class_method :normalize_suggestion_count, :normalize_keywords, :normalize_item

  def self.call_gpt_api(prompt)
    uri = URI(GPT_API_URL)
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["Authorization"] = "Bearer #{ENV['GPT_API_KEY']}"

    payload = {
      model: MODEL_NAME,
      messages: [
        { role: "system", content: "あなたはサービス設計の専門家です。指定されたJSONフォーマットのオブジェクトのみを返却してください。" },
        { role: "user", content: prompt }
      ],
      response_format: { type: "json_object" },
      temperature: 0.7
    }
    req.body = payload.to_json

    begin
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 120) do |http|
        http.request(req)
      end

      if res.is_a?(Net::HTTPSuccess)
        JSON.parse(res.body)
      else
        Rails.logger.error("SubCategorySuggestionService: APIエラー #{res.code} #{res.body}")
        nil
      end
    rescue => e
      Rails.logger.error("SubCategorySuggestionService: API通信エラー: #{e.message}")
      nil
    end
  end

  private_class_method :call_gpt_api
end
