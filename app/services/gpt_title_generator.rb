require "net/http"
require "json"
require "openssl"

class GptTitleGenerator
  MODEL_NAME = "gpt-4o-mini"
  GPT_API_URL = "https://api.openai.com/v1/chat/completions"

  # ==========================================================
  # 親記事（Pillar）に関連する魅力的な子記事タイトルを生成
  # ==========================================================
  def self.generate_titles(pillar_column)
    unless pillar_column&.title.present?
      Rails.logger.error("GptTitleGenerator: 親記事のタイトルが空です")
      return []
    end

    # ジャンル情報の取得（GenreRegistryを利用）
    target_category = detect_category(pillar_column)
    service_info = GenreRegistry.service_profile(target_category)
    
    # 重複回避のため、既存の子記事タイトルを取得
    existing_titles = Column.where(parent_id: pillar_column.id).pluck(:title)
    existing_titles_text = existing_titles.any? ? "既存タイトル: #{existing_titles.join(', ')}" : "既存の子記事はありません。"

    prompt = <<~PROMPT
      あなたは高度なSEO戦略家です。親記事（ピラーページ）「#{pillar_column.title}」を支える、強力なトピッククラスター（子記事）のタイトル案を15個から25個の間で生成してください。

      # 背景情報
      - 業種カテゴリ: #{target_category}
      - 専門サービス強み: #{service_info}
      
      # 記事選定の条件（厳守）
      1. SEOの魅力: 検索ボリュームが期待でき、親記事のキーワードと相乗効果があること。
      2. ユーザーの魅力: 読者の悩み、不安、疑問を解決する具体的でベネフィットが明確なタイトル。
      3. 重複の禁止: #{existing_titles_text} と内容や意味が被らないこと。
      4. ジャンル遵守: 必ず「#{target_category}」のドメインに関連したトピックであること。
      5. 階層性: 親記事で解説しきれなかった「手順」「注意点」「比較」「費用感」などを深掘りすること。

      # 出力形式
      JSON形式のみで回答してください。
      {
        "cluster_titles": [
          { "title": "タイトル案" }
        ]
      }
    PROMPT

    res = call_gpt_api(prompt)
    return [] if res.nil?

    begin
      json_content = JSON.parse(res.dig("choices", 0, "message", "content"))
      json_content["cluster_titles"] || []
    rescue => e
      Rails.logger.error("GptTitleGenerator: タイトルパースエラー: #{e.message}")
      []
    end
  end

  private

  # GenreRegistryのキーワードを用いてカテゴリを判定
  def self.detect_category(column)
    search_text = "#{column.title} #{column.keyword} #{column.genre} #{column.choice}"
    GenreRegistry::GENRES.each do |key, data|
      if data[:keywords].any? { |w| search_text.include?(w) }
        return data[:ja]
      end
    end
    "その他"
  end

  def self.call_gpt_api(prompt)
    uri = URI(GPT_API_URL)
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["Authorization"] = "Bearer #{ENV['GPT_API_KEY']}"

    payload = {
      model: MODEL_NAME,
      messages: [
        { role: "system", content: "あなたはSEOコンサルタントです。JSON形式で回答してください。余計な解説は不要です。" },
        { role: "user", content: prompt }
      ],
      response_format: { type: "json_object" },
      temperature: 0.6 # 戦略的な多様性を出すために少し高めに設定
    }
    req.body = payload.to_json

    begin
      # タイムアウト設定
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