class EvaluateColumnQualityJob < ApplicationJob
  queue_as :article_evaluation

  AXIS_KEYS = %w[structure seo readability usefulness originality].freeze
  BODY_EXCERPT_LIMIT = 6_000

  def perform(column_id)
    column = Column.find_by(id: column_id)
    return unless column
    return unless column.body.present?

    begin
      evaluation = evaluate_article_quality(column)

      column.update!(
        quality_score:      evaluation[:overall_score],
        evaluation_metrics: evaluation[:metrics]
      )

      GenerationChannelBroadcaster.broadcast(
        status: "evaluated",
        column_id: column.id,
        quality_score: evaluation[:overall_score],
        evaluation_metrics: evaluation[:metrics]
      )

      Rails.logger.info("✅ Article evaluation completed: #{column.id} - Score: #{evaluation[:overall_score]}")
    rescue => e
      Rails.logger.error("❌ Article evaluation failed: #{column.id} - #{e.message}")
    end
  end

  private

  def evaluate_article_quality(column)
    structure = analyze_body_structure(column.body)
    prompt = GptGenerationLocale.with_language(column) do
      GptGenerationLocale.prepare_user_prompt(build_evaluation_prompt(column, structure))
    end

    response_text = call_openai_api(prompt)
    parse_evaluation_response(response_text)
  end

  def build_evaluation_prompt(column, structure)
    keyword_line = column.keyword.present? ? "ターゲットキーワード: #{column.keyword}" : "ターゲットキーワード: （未設定）"
    genre_line = column.genre.present? ? "ジャンル: #{column.genre}" : ""

    <<~PROMPT
      あなたはWeb記事の品質監査者です。以下の記事を5つの評価軸で採点してください。
      各軸は0〜20点（整数）で厳密に評価し、甘い採点は避けてください。
      80点以上は本当に優秀な記事のみ、60点未満は明確な改善が必要な記事に付けてください。
      記事ごとに差がつくよう、根拠に基づいて採点してください。

      【評価軸】
      - structure（構成）: 見出し階層、論理展開、情報の過不足
      - seo（SEO）: キーワードの自然な配置、検索意図への適合、タイトルとの整合
      - readability（読みやすさ）: 文の長さ、段落構成、専門用語の説明
      - usefulness（有用性）: 読者の課題解決度、具体性、信頼できる情報か
      - originality（独自性）: 一般的な内容の繰り返しでなく、独自の視点や価値があるか

      【記事情報】
      タイトル: #{column.title}
      #{keyword_line}
      #{genre_line}
      文字数（概算）: #{structure[:char_count]}
      見出し数: H2 #{structure[:h2_count]}件 / H3 #{structure[:h3_count]}件
      段落数（概算）: #{structure[:paragraph_count]}

      【記事本文】
      #{body_excerpt(column.body)}

      回答は以下のJSON形式のみで返してください（余計な説明・マークダウン不要）:
      {
        "axes": {
          "structure":   { "score": <0〜20>, "note": "<1文の根拠>" },
          "seo":         { "score": <0〜20>, "note": "<1文の根拠>" },
          "readability": { "score": <0〜20>, "note": "<1文の根拠>" },
          "usefulness":  { "score": <0〜20>, "note": "<1文の根拠>" },
          "originality": { "score": <0〜20>, "note": "<1文の根拠>" }
        },
        "feedback": "<2〜3文の総評。強みと改善点を具体的に>"
      }
    PROMPT
  end

  def analyze_body_structure(body)
    text = body.to_s
    plain = text.gsub(/<[^>]+>/, " ")

    {
      h2_count: text.scan(/<h2[\s>]/i).size + text.scan(/^##\s/m).size,
      h3_count: text.scan(/<h3[\s>]/i).size + text.scan(/^###\s/m).size,
      char_count: plain.gsub(/\s+/, "").length,
      paragraph_count: plain.split(/\n{2,}/).count { |p| p.strip.length > 20 }
    }
  end

  def body_excerpt(body)
    text = body.to_s
    return text if text.length <= BODY_EXCERPT_LIMIT

    head = text[0, 3_500]
    tail = text[-1_500, 1_500]
    "#{head}\n\n…（中略 #{text.length - 5_000}文字）…\n\n#{tail}"
  end

  def call_openai_api(prompt)
    unless ENV["GPT_API_KEY"].present?
      Rails.logger.warn("⚠️ GPT_API_KEY is not set. Using mock evaluation data.")
      return mock_evaluation_response
    end

    uri = URI.parse("https://api.openai.com/v1/chat/completions")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 90

    request = Net::HTTP::Post.new(uri.path, {
      "Content-Type"  => "application/json",
      "Authorization" => "Bearer #{ENV['GPT_API_KEY']}"
    })

    request.body = {
      model: "gpt-4o-mini",
      temperature: 0.4,
      messages: [
        {
          role:    "system",
          content: "あなたはWebコンテンツの品質評価の専門家です。採点は厳格かつ一貫性を持たせ、指示されたJSON形式のみで回答してください。"
        },
        {
          role:    "user",
          content: prompt
        }
      ]
    }.to_json

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise "OpenAI API error: #{response.code} #{response.body}"
    end

    body    = JSON.parse(response.body)
    content = body.dig("choices", 0, "message", "content").to_s.strip
    content.gsub(/\A```(?:json)?\s*/i, "").gsub(/\s*```\z/, "").strip
  end

  def mock_evaluation_response
    axes = AXIS_KEYS.index_with do
      score = rand(10..18)
      { "score" => score, "note" => "モック評価データです。" }
    end

    {
      "axes"     => axes,
      "feedback" => "APIキーが設定されていないため、モック評価データを使用しています。実際の評価にはGPT_API_KEY環境変数を設定してください。"
    }.to_json
  end

  def parse_evaluation_response(json_text)
    parsed = JSON.parse(json_text)
    axes = normalize_axes(parsed["axes"])
    overall = axes.values.sum { |axis| axis[:score].to_f }.round(1).clamp(0.0, 100.0)

    {
      overall_score: overall,
      metrics: {
        axes: axes.transform_values { |axis| { score: axis[:score], note: axis[:note] } },
        feedback: parsed["feedback"].to_s
      }
    }
  rescue JSON::ParserError => e
    Rails.logger.error("❌ JSON parse error in EvaluateColumnQualityJob: #{e.message} / raw: #{json_text}")
    { overall_score: 0.0, metrics: { feedback: "評価の解析に失敗しました。" } }
  end

  def normalize_axes(raw_axes)
    raw = raw_axes.is_a?(Hash) ? raw_axes : {}

    AXIS_KEYS.index_with do |key|
      axis = raw[key] || raw[key.to_sym] || {}
      score = axis["score"].to_i.clamp(0, 20)
      note  = axis["note"].to_s.strip.presence || ""
      { score: score, note: note }
    end
  end
end
