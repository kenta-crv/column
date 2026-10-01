# frozen_string_literal: true

require "test_helper"

class HiraganaArticleGenerationPipelineTest < ActiveSupport::TestCase
  test "hiragana is kept for saved articles and is not selectable or generatable" do
    saved = Column.create!(
      title: "ほけんしょう",
      article_type: "pillar",
      genre: "other",
      status: "draft",
      language: "hiragana"
    )

    assert_equal %w[ja en], Column::SELECTABLE_LANGUAGES
    refute_includes Column::SELECTABLE_LANGUAGES, "hiragana"
    assert saved.hiragana_article?
    assert_equal "hiragana", Column.language_for_save("hiragana", saved)
    assert_equal "ja", Column.language_for_save("hiragana", Column.new)
    assert_equal "ja", Column.normalize_selectable_language("hiragana")
    refute GptPromptPack::ROOT.join("hiragana.yml").exist?
    refute defined?(GptHiraganaArticleGenerator)

    japanese = Column.new(article_type: "pillar", generation_mode: "default", language: "ja")
    assert_equal GptPillarGenerator, ColumnBodyGenerator.service_class_for(japanese)

    error = assert_raises(StandardError) { ColumnBodyGenerator.generate!(saved) }
    assert_equal "ひらがなの生成は停止しています", error.message
    assert_raises(StandardError) { ColumnBodyGenerator.service_class_for(saved) }
  end
end
