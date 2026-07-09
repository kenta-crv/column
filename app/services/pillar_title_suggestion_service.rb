require "net/http"
require "json"
require "openssl"

class PillarTitleSuggestionService
  MODEL_NAME = "gpt-4o-mini"
  GPT_API_URL = "https://api.openai.com/v1/chat/completions"
  DEFAULT_SUGGESTION_COUNT = 10
  MAX_SUGGESTION_COUNT = 30

  # ==========================================================
  # キーワードとターゲット層から親記事（Pillar）タイトルを生成
  # ==========================================================
  def self.call(keyword1:, keyword2:, target_layer:, genre:, custom_prompt: nil, suggestion_count: nil, client: nil)
    if keyword1.blank? || keyword2.blank? || genre.blank?
      Rails.logger.error("PillarTitleSuggestionService: 必須パラメータが不足しています")
      return { success: false, error: "必須パラメータが不足しています", titles: [] }
    end

    genre_key = GenreRegistry.resolve_key(genre, client: client)
    genre_label = GenreRegistry.to_ja(genre_key, client: client) || genre.to_s
    service_info = GenreRegistry.service_profile(genre_key, client: client)
    title_count = normalize_suggestion_count(suggestion_count)

    target_layer_description = case target_layer
    when "big"
      "ビッグキーワード：検索ボリュームが大きく、広範なユーザー層を対象とする包括的なトピック"
    when "middle"
      "ミドルキーワード：検索ボリュームが中程度で、特定のニーズや関心を持つユーザー層を対象とするトピック"
    when "small"
      "スモールキーワード：検索ボリュームは少ないが、購買意欲の高い具体的なニーズを持つユーザー層を対象とするトピック"
    else
      "一般的なトピック"
    end

    custom_prompt_section = if custom_prompt.present?
      <<~SECTION

      # 追加指示（最優先）
      以下の指示を必ず反映してください。
      #{custom_prompt.strip}
      SECTION
    else
      ""
    end

    prompt = <<~PROMPT
      # あなたの役割
      あなたは高度なSEO戦略家およびコンテンツマーケターです。
      与えられたキーワードとターゲット層に基づいて、検索エンジンとユーザーの双方から高く評価される「親記事（ピラーページ）タイトル案」を#{title_count}個生成してください。

      # 入力データ
      - キーワード1: #{keyword1}
      - キーワード2: #{keyword2}
      - ターゲット層: #{target_layer_description}
      - 業種カテゴリ: #{genre_label}
      - 専門サービス強み: #{service_info}
      - 提案数: #{title_count}個（必ず#{title_count}個生成すること）
      #{custom_prompt_section}
      # タイトル選定の条件（厳守）
      1. 【最重要】ターゲット層への完全な適合:
         指定されたターゲット層（#{target_layer}）の特性に完全に合致したトーンと切り口でタイトルを作成してください。
         ビッグキーワードの場合は包括的で網羅的な内容を、ミドルキーワードの場合は特定のニーズに焦点を当てた内容を、スモールキーワードの場合は具体的で実用的な内容を示唆するタイトルにしてください。

      2. キーワードの自然な統合:
         提示された2つのキーワード（#{keyword1}、#{keyword2}）を自然な形でタイトルに統合してください。
         キーワードを無理に詰め込むのではなく、読みやすく魅力的な日本語として成立させることを優先してください。

      3. 業種カテゴリとの整合性:
         必ず「#{genre_label}」のドメインに関連した範囲内で、かつ業種の専門性を活かしたタイトルにしてください。
         サービスの強み（#{service_info}）を反映させ、信頼性と専門性を感じさせるタイトルにしてください。

      4. クリック誘導性:
         ユーザーがクリックしたくなるような魅力的な表現を使用してください。
         「完全ガイド」「徹底解説」「初心者向け」「比較」「選び方」など、検索意図に合致したパワーワードを適切に活用してください。

      5. 多様性の確保:
         #{title_count}個のタイトル案について、異なるアプローチをバランスよく含めてください：
         - 包括的なガイド系タイトル
         - 具体的な解決策系タイトル
         - 比較・選定系タイトル
         - トラブル解決系タイトル
         - トレンド・最新情報系タイトル
         - 初心者向け・基礎系タイトル

      # 出力形式
      JSON形式のみで回答してください。余計な文字列（```json などのマークダウンやバッククォート）や解説のテキストは一切含めないでください。
      titles 配列には必ず #{title_count} 件のタイトルを含めてください。
      {
        "titles": [
          { "title": "タイトル案1" },
          { "title": "タイトル案2" }
        ]
      }
    PROMPT

    res = call_gpt_api(prompt)
    return { success: false, error: "API通信エラーが発生しました", titles: [] } if res.nil?

    begin
      json_content = JSON.parse(res.dig("choices", 0, "message", "content"))
      titles = json_content["titles"] || []
      { success: true, titles: titles.map { |t| t["title"] }.compact.reject(&:blank?) }
    rescue => e
      Rails.logger.error("PillarTitleSuggestionService: タイトルパースエラー: #{e.message}")
      { success: false, error: "タイトルの解析に失敗しました", titles: [] }
    end
  end

  def self.normalize_suggestion_count(value)
    count = value.to_i
    count = DEFAULT_SUGGESTION_COUNT if count <= 0
    [count, MAX_SUGGESTION_COUNT].min
  end

  private_class_method :normalize_suggestion_count

  private

  def self.call_gpt_api(prompt)
    uri = URI(GPT_API_URL)
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["Authorization"] = "Bearer #{ENV['GPT_API_KEY']}"

    payload = {
      model: MODEL_NAME,
      messages: [
        { role: "system", content: "あなたはSEOコンサルタントです。指定されたJSONフォーマットのオブジェクトのみを返却してください。マークダウンの枠組みやバッククォート、解説のテキストは一切不要です。" },
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
        Rails.logger.error("PillarTitleSuggestionService: APIエラー #{res.code} #{res.body}")
        nil
      end
    rescue => e
      Rails.logger.error("PillarTitleSuggestionService: API通信エラー: #{e.message}")
      nil
    end
  end
end
