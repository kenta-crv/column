class EvaluateColumnQualityJob < ApplicationJob
  queue_as :article_evaluation

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

      # ✅ 評価完了をActionCableでブロードキャスト（リアルタイム反映用）
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
    prompt = <<~PROMPT
      以下の記事を100点満点で総合評価してください。

      評価は記事全体を読んだうえで、読者にとっての有用性・信頼性・読みやすさ・独自性・構成を総合的に判断し、
      0〜100の整数または小数1桁のスコアを1つだけ算出してください。
      評価軸を個別に返す必要はありません。

      記事タイトル: #{column.title}
      記事本文:
      #{column.body[0..3000]}

      回答は以下のJSON形式のみで返してください（余計な説明・マークダウン不要）:
      {
        "overall_score": <0〜100のスコア>,
        "feedback": "<2〜3文の簡潔な総評>"
      }
    PROMPT

    response_text = call_openai_api(prompt)
    parse_evaluation_response(response_text)
  end

  def call_openai_api(prompt)
    # APIキーが設定されていない場合はモックデータを返す
    unless ENV['GPT_API_KEY'].present?
      Rails.logger.warn("⚠️ GPT_API_KEY is not set. Using mock evaluation data.")
      return mock_evaluation_response
    end

    uri = URI.parse("https://api.openai.com/v1/chat/completions")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60

    request = Net::HTTP::Post.new(uri.path, {
      "Content-Type"  => "application/json",
      "Authorization" => "Bearer #{ENV['GPT_API_KEY']}"
    })

    request.body = {
      model: "gpt-4o-mini",
      temperature: 0.2,
      messages: [
        {
          role:    "system",
          content: "あなたはWebコンテンツの品質評価の専門家です。指示されたJSON形式のみで回答してください。"
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

    # ```json ... ``` フェンスが付いていた場合も安全に除去
    content.gsub(/\A```(?:json)?\s*/i, "").gsub(/\s*```\z/, "").strip
  end

  def mock_evaluation_response
    # APIキーがない場合のフォールバックモックデータ
    {
      "overall_score" => rand(75.0..95.0).round(1),
      "feedback" => "APIキーが設定されていないため、モック評価データを使用しています。実際の評価にはOPENAI_API_KEY環境変数を設定してください。"
    }.to_json
  end

  def parse_evaluation_response(json_text)
    parsed = JSON.parse(json_text)

    overall = parsed["overall_score"].to_f.clamp(0.0, 100.0)

    {
      overall_score: overall,
      metrics: {
        feedback: parsed["feedback"].to_s
      }
    }
  rescue JSON::ParserError => e
    Rails.logger.error("❌ JSON parse error in EvaluateColumnQualityJob: #{e.message} / raw: #{json_text}")
    { overall_score: 0.0, metrics: { feedback: "評価の解析に失敗しました。" } }
  end
end