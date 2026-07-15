require "net/http"
require "json"

class GenreQuickSetupService
  MODEL_NAME = "gpt-4o-mini"
  GPT_API_URL = "https://api.openai.com/v1/chat/completions"

  def self.call(service_name:, strong_points:, keywords: nil, keyword1: nil, keyword2: nil, sub_category_limit: 0)
    if service_name.blank? && strong_points.blank?
      return { success: false, error: "サービス名または訴求ポイントを入力してください" }
    end

    keyword_list = [
      keywords,
      [keyword1, keyword2].compact.join("、").presence
    ].compact.join("、")

    sub_limit = sub_category_limit.to_i
    sub_section = if sub_limit.positive?
      <<~SECTION

      # 中分類
      中分類は最大#{sub_limit}件まで。記事の sub_genre として使える切り口で、重複の少ない内容にしてください。
      sub_categories 配列には 0〜#{sub_limit} 件を含めてください（推奨は1件）。
      SECTION
    else
      <<~SECTION

      # 中分類
      sub_categories は空配列 [] にしてください。
      SECTION
    end

    prompt = <<~PROMPT
      # あなたの役割
      あなたはBtoB/BtoCサービスのマーケティング戦略家です。
      入力情報から、記事生成に使う大ジャンル（サービス・ジャンル）の下書きを作成してください。

      # 入力
      - サービス名: #{service_name.presence || "（未入力）"}
      - 訴求ポイント:
      #{strong_points.presence || "（未入力）"}
      - 参考キーワード: #{keyword_list.presence || "（未入力）"}
      #{sub_section}
      # 出力ルール
      1. key は英小文字・数字・アンダースコアのみ（例: office_cleaning, riplus_consulting）
      2. ja は日本語の表示名（必須）
      3. service_name はサービス名（未入力なら ja から推測）
      4. strong_points は訴求ポイントを3〜5行程度で具体化
      5. keywords は参考キーワード配列（3〜8件）
      6. 中分類がある場合、key/name/target/description/features/keywords/price_hint/area/strengths/industry_weakness を具体的に

      # 出力形式
      JSON形式のみで回答してください。
      {
        "key": "example_key",
        "ja": "表示名",
        "service_name": "サービス名",
        "strong_points": "訴求ポイント",
        "keywords": ["キーワード1", "キーワード2"],
        "sub_categories": []
      }
    PROMPT

    res = call_gpt_api(prompt)
    return { success: false, error: "API通信エラーが発生しました" } if res.nil?

    begin
      json = JSON.parse(res.dig("choices", 0, "message", "content"))
      draft = normalize_draft(json, sub_limit)
      if draft[:key].blank? || draft[:ja].blank?
        { success: false, error: "ジャンル下書きの解析に失敗しました" }
      else
        { success: true, draft: draft }
      end
    rescue => e
      Rails.logger.error("GenreQuickSetupService: パースエラー: #{e.message}")
      { success: false, error: "ジャンル下書きの解析に失敗しました" }
    end
  end

  def self.normalize_draft(json, sub_limit)
    key = json["key"].to_s.strip.downcase
    sub_items = Array(json["sub_categories"]).first(sub_limit).map do |item|
      SubCategorySuggestionService.format_sub_category_item(item)
    end.reject { |item| item[:key].blank? || item[:name].blank? }

    {
      key: key,
      ja: json["ja"].to_s.strip,
      service_name: json["service_name"].to_s.strip.presence || json["ja"].to_s.strip,
      strong_points: json["strong_points"].to_s.strip,
      keywords: Array(json["keywords"]).map(&:to_s).map(&:strip).reject(&:blank?),
      sub_categories: sub_items
    }
  end

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
        Rails.logger.error("GenreQuickSetupService: APIエラー #{res.code} #{res.body}")
        nil
      end
    rescue => e
      Rails.logger.error("GenreQuickSetupService: API通信エラー: #{e.message}")
      nil
    end
  end

  private_class_method :normalize_draft, :call_gpt_api
end
