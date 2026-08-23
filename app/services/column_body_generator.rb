# frozen_string_literal: true

# generation_mode に応じて本文生成サービスを解決する。
# 通常ベース (GptPillarGenerator / GptArticleGenerator) のプロンプトは変更・差し替えしない。
#
# 注意:
# - 他社比較ロジック（比較対象の指定/自動発見）は gpt_pillar_recommendation.rb 側に実装されている。
# - そのため「比較」モードは GptPillarRecommendation を使う。
# - 「自社宣伝」モードは gpt_pillar_comparison.rb（自社事実＋推薦軸中心）を使う。
class ColumnBodyGenerator
  class EmptyOutputError < StandardError; end

  MODE_SERVICES = {
    "comparison" => "GptPillarRecommendation",
    "recommendation" => "GptPillarComparison",
    "note" => "GptPillarNote",
    "qiita" => "GptPillarQiita",
    "zenn" => "GptPillarZenn"
  }.freeze

  # :managed = サービス側で column を更新済み
  # String  = 子記事通常生成の本文（呼び出し側で保存）
  def self.generate!(column)
    GptGenerationLocale.with_language(column) do
      mode = Column.normalize_generation_mode_for(column.generation_mode, language: column.language)

      if mode == "default"
        if column.article_type == "pillar"
          GptPillarGenerator.generate_full_from_existing_column!(column)
          return :managed
        end

        return GptArticleGenerator.generate_body(column)
      end

      MODE_SERVICES.fetch(mode).constantize.generate_full_from_existing_column!(column)
      :managed
    end
  end

  def self.service_class_for(column)
    mode = Column.normalize_generation_mode_for(column.generation_mode, language: column.language)

    if mode == "default"
      return column.article_type == "pillar" ? GptPillarGenerator : GptArticleGenerator
    end

    MODE_SERVICES.fetch(mode).constantize
  end

  def self.cancelled_error?(error)
    error.class.name.end_with?("::GenerationCancelledError")
  end
end
