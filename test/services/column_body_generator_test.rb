# frozen_string_literal: true

require "test_helper"

class ColumnBodyGeneratorTest < ActiveSupport::TestCase
  test "normalize_generation_mode falls back to default" do
    assert_equal "default", Column.normalize_generation_mode(nil)
    assert_equal "default", Column.normalize_generation_mode("unknown")
    assert_equal "comparison", Column.normalize_generation_mode("comparison")
    assert_equal "recommendation", Column.normalize_generation_mode("recommendation")
    assert_equal "note", Column.normalize_generation_mode("note")
  end

  test "attributes_for_child_generation copies mode prompt and language" do
    pillar = Column.new(
      title: "親",
      article_type: "pillar",
      generation_mode: "comparison",
      prompt: "比較対象：A社",
      language: "en"
    )

    attrs = Column.attributes_for_child_generation(pillar)
    assert_equal "comparison", attrs[:generation_mode]
    assert_equal "比較対象：A社", attrs[:prompt]
    assert_equal "en", attrs[:language]
  end

  test "service wiring matrix" do
    # 他社比較ロジックは recommendation.rb 側にあるため、比較モードはそちらを使う
    expected = {
      ["pillar", "default"] => GptPillarGenerator,
      ["pillar", "comparison"] => GptPillarRecommendation,
      ["pillar", "recommendation"] => GptPillarComparison,
      ["pillar", "note"] => GptPillarNote,
      ["pillar", "qiita"] => GptPillarQiita,
      ["pillar", "zenn"] => GptPillarZenn,
      ["child", "default"] => GptArticleGenerator,
      ["child", "comparison"] => GptPillarRecommendation,
      ["child", "recommendation"] => GptPillarComparison,
      ["cluster", "comparison"] => GptPillarRecommendation
    }

    expected.each do |(type, mode), klass|
      column = Column.new(article_type: type, generation_mode: mode, language: "ja")
      assert_equal klass, ColumnBodyGenerator.service_class_for(column), "#{type}/#{mode}"
    end
  end

  test "english articles do not use note qiita or zenn generators" do
    %w[note qiita zenn].each do |mode|
      column = Column.new(article_type: "pillar", generation_mode: mode, language: "en")
      assert_equal "default", Column.normalize_generation_mode_for(mode, language: "en")
      assert_equal GptPillarGenerator, ColumnBodyGenerator.service_class_for(column)
    end
  end
end
