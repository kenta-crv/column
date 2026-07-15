module ColumnsHelper
  AXIS_LABELS = QualityScorePresenter::AXIS_LABELS

  def columns_index_link(genre_key, label_text = nil)
    return unless GenreRegistry.genre_keys.include?(genre_key.to_s)

    text = label_text || "#{genre_key.titleize} コラム一覧"
    link_to text, columns_index_path(genre: genre_key), class: "btn btn-primary"
  end

  def quality_score_cell(column)
    score = column.quality_score
    return content_tag(:div, "評価待ち", class: "quality-score-pending") unless QualityScorePresenter.scored?(score)

    metrics = column.evaluation_metrics
    level_class = QualityScorePresenter.level_class(score)
    tooltip_lines = QualityScorePresenter.tooltip_lines(score, metrics)

    content_tag(:div, class: "quality-score-cell has-tooltip") do
      safe_join([
        content_tag(:div, score.round(1), class: "quality-score-value #{level_class}"),
        quality_score_tooltip_markup(tooltip_lines, metrics)
      ])
    end
  end

  private

  def quality_score_tooltip_markup(lines, metrics)
    return "".html_safe if lines.blank?

    feedback = QualityScorePresenter.normalize_metrics(metrics)["feedback"]

    content_tag(:div, class: "quality-score-tooltip", role: "tooltip") do
      safe_join(lines.map.with_index do |line, index|
        css_class =
          if index.zero?
            "tooltip-line tooltip-line--overall"
          elsif line.include?("/20")
            "tooltip-line tooltip-line--axis"
          elsif feedback.present? && line == feedback
            "tooltip-line tooltip-line--feedback"
          else
            "tooltip-line"
          end
        content_tag(:div, line, class: css_class)
      end)
    end
  end
end
