require "test_helper"

class QualityScorePresenterTest < ActiveSupport::TestCase
  test "tooltip_lines includes overall, axes, and feedback" do
    metrics = {
      "axes" => {
        "structure" => { "score" => 16, "note" => "見出しが明確" },
        "seo" => { "score" => 14, "note" => "キーワード配置は良好" }
      },
      "feedback" => "総合的に読みやすい記事です。"
    }

    lines = QualityScorePresenter.tooltip_lines(76.5, metrics)

    assert_equal "総合: 76.5点", lines.first
    assert_includes lines, "構成: 16/20 — 見出しが明確"
    assert_equal "総合的に読みやすい記事です。", lines.last
  end

  test "level_class buckets scores" do
    assert_equal "score-high", QualityScorePresenter.level_class(82)
    assert_equal "score-mid", QualityScorePresenter.level_class(70)
    assert_equal "score-low", QualityScorePresenter.level_class(55)
  end
end
