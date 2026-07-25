module ColumnsHelper
  AXIS_LABELS = QualityScorePresenter::AXIS_LABELS

  # J Work Column 下部の LINE 導線（中ジャンルで切り替え）
  # nil / delivery_partner → 新規取引相談
  # driver_recruitment → お仕事の応募
  JWORK_LINE_CTAS = {
    "delivery_partner" => {
      kind: "business",
      badge: "法人向け",
      title: "新規取引のご相談はLINEで",
      lead: "Amazon配送の人材確保・業務請負について、まずはお気軽にご相談ください。",
      cta_label: "新規取引相談",
      url: "https://lin.ee/NZBWRrsD",
      qr_url: "https://qr-official.line.me/gs/M_697qedfz_GW.png?oat_content=qr",
      banner_path: "/images/line-cta-business.webp"
    },
    "driver_recruitment" => {
      kind: "recruit",
      badge: "求職者向け",
      title: "お仕事の応募はLINEで",
      lead: "Amazon配送ドライバーのお仕事情報をLINEで受け取れます。未経験の方も歓迎です。",
      cta_label: "お仕事の応募",
      url: "https://lin.ee/8pGADE1",
      qr_url: "https://qr-official.line.me/gs/M_522jmsbm_GW.png?oat_content=qr",
      banner_path: "/images/line-cta-recruit.webp"
    }
  }.freeze

  def columns_index_link(genre_key, label_text = nil)
    key = genre_key.to_s
    return unless key.match?(/\A[a-z0-9_]+\z/)

    text = label_text || "#{key.titleize} コラム一覧"
    link_to text, columns_index_path(genre: key), class: "btn btn-primary"
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

  def show_jwork_line_cta?(column)
    return false if column.blank?
    return false if can_manage_column?(column)
    return false if client_signed_in?
    return false if platform_host?

    public_request_host == "j-work.jp"
  end

  def jwork_line_cta_for(column)
    key = resolve_column_sub_genre(column).to_s
    key = "delivery_partner" unless JWORK_LINE_CTAS.key?(key)
    JWORK_LINE_CTAS[key]
  end

  def resolve_column_sub_genre(column)
    return nil if column.blank?

    column.sub_genre.presence || column.parent&.sub_genre.presence
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
