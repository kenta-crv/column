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
    
    existing_titles = Column.where(parent_id: pillar_column.id).pluck(:title)
    existing_titles_text = existing_titles.present? ? existing_titles.join("\n") : "（なし）"

    # 親タイトルから構成要素（単語セグメント）を動的に抽出
    extracted_elements = extract_title_elements(pillar_column.title)

    prompt = <<~PROMPT
      # あなたの役割
      あなたは高度なSEO戦略家およびコンテンツマーケターです。
      与えられた親記事（ピラーページ）のタイトルが持つ「本質的な主旨、性質、ターゲット、および世界観」をそのまま忠実に引き継いだ、検索エンジンとユーザーの双方から高く評価される「トピッククラスター（子記事）タイトル案」を15個から25個の間で生成してください。

      # 対象となる親記事（Pillar）データ
      - 親タイトル: #{pillar_column.title}
      - 業種カテゴリ: #{target_category}
      - 専門サービス強み: #{service_info}

      # 必須分析対象（親タイトルの構成要素）
      - 抽出された構成要素: #{extracted_elements.join(', ')}

      # 記事選定の条件（厳守）
      1. 【最重要】親タイトルの「方向性・ニュアンス」への完全な同調:
         親タイトルが提示している【主旨の性質（文字通りの意味、トーン、目的意識、訴求している方向性）】を正確に捉え、生成する子記事すべての切り口・トーンをその性質に100%合致させてください。
         親タイトルの持つ性質やニュアンスを勝手に改変したり、親タイトルの文字情報に含まれていない異なる性質へ偏らせることを完全に禁止します。親タイトルのトーンをそのまま美しくブレイクダウンしたバリエーションを作成してください。

      2. 構成要素の完全な掛け合わせ（マルチアングル）:
         単一の業種カテゴリ名や、特定の単一キーワードだけに依存した、どのシーンでも使い回せるような表面的な汎用記事タイトルの量産を完全に禁止します。
         必ず、提示された「親タイトル」および「抽出された構成要素」に存在する【すべての構成要素】を適切にサンプリングして掛け合わせ、その親記事の文脈の枠内でしか成立しない、具体的かつ個別の切実な需要を捉えたタイトルにしてください。

      3. トピックの立体的な網羅性:
         条件1の方向性を完全に維持したまま、「アプローチする対象・属性別の切り口」「具体的なシーン・周辺環境別の切り口」「運用・戦略面での切り口」など、異なる角度からバランスよくスポットを当て、クラスター全体で親トピックの全容を立体的に補完してください。

      4. 重複の禁止と類似の許可:
         既に存在する以下の子記事タイトルと内容が完全に被らないこと。ただしPillarの枝葉となるため、異なる切り口でのアプローチは許可します。
         [既存のタイトル一覧]
         #{existing_titles_text}

      5. 階層性とドメインの整合性:
         必ず「#{target_category}」のドメインに関連した範囲内で、かつ親タイトルの目的や提供価値から一切乖離しないこと。

      # 出力形式
      JSON形式のみで回答してください。余計な文字列（```json などのマークダウンやバッククォート）や解説のテキストは一切含めないでください。
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

  # 親タイトルから特定の業種に依存せず、機械的にキーワードを抽出するメソッド
  def self.extract_title_elements(title)
    return [] if title.blank?
    
    # 記号や一般的な助詞・区切り文字をスペースに置換して分割
    cleaned = title.gsub(/[？\?！\!。、：:・「」『』【】（）()|\/]/, ' ')
    words = cleaned.split(/[\s　]+/)
    
    # 2文字以上の重複しない塊を抽出し、LLMに必須掛け合わせ要素のヒントとして渡す
    words.select { |w| w.length >= 2 }.uniq
  end

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
      temperature: 0.6
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