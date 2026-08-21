# frozen_string_literal: true

# 空ファイルのままコミットされていたため、クラス定義のみ復元する。
# ai_article と ai_article_generation は GenreRegistry / seeds 上で別テンプレートとして
# 残っているため、ここではデータを書き換えない。
class UnifyAiArticleGenerationToAiArticle < ActiveRecord::Migration[6.1]
  def up; end

  def down; end
end
