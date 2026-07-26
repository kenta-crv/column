module ColumnsHelper
  AXIS_LABELS = QualityScorePresenter::AXIS_LABELS

  # 公開記事の title / description / OG / Twitter / article meta を一括設定する
  def apply_column_seo_meta_tags(column)
    return if column.blank?

    desc = column_seo_description(column)
    image = column_seo_image_url(column)
    site_name = column_seo_site_name(column)
    page_url = public_absolute_url(request.path)

    tags = {
      title: column.title,
      description: desc,
      canonical: page_url,
      og: {
        title: column.title,
        description: desc,
        type: "article",
        url: page_url,
        site_name: site_name
      },
      twitter: {
        card: image.present? ? "summary_large_image" : "summary",
        title: column.title,
        description: desc
      },
      article: {
        published_time: column.published_at&.iso8601,
        modified_time: column.updated_at&.iso8601,
        section: column.genre_label.presence
      }
    }
    tags[:keywords] = column.keyword if column.keyword.present?
    if image.present?
      tags[:og][:image] = image
      tags[:twitter][:image] = image
    end

    set_meta_tags(tags)
  end

  def column_seo_description(column)
    raw = column.description.to_s.strip
    return raw if raw.present? && raw != column.title.to_s.strip

    excerpt = strip_tags(column.body.to_s).to_s.gsub(/\s+/, " ").strip
    return truncate(excerpt, length: 120, omission: "…") if excerpt.present?

    column.title.to_s
  end

  def column_seo_site_name(column)
    resolved = GenreRegistry.resolve_key(column.genre)
    key = GenreRegistry.canonical_key(resolved.presence || column.genre_key || column.genre)
    GenreRegistry.genres.dig(key&.to_sym, :service_name).presence || "Drafity"
  end

  def column_seo_image_url(column)
    return if column.file.blank?

    path = column.file.url.presence || column.file.to_s
    return if path.blank?

    return path if path.start_with?("http://", "https://")

    public_absolute_url(path.start_with?("/") ? path : "/#{path}")
  end

  def column_article_json_ld(column)
    site_name = column_seo_site_name(column)
    page_url = public_absolute_url(request.path)
    image = column_seo_image_url(column)

    data = {
      "@context" => "https://schema.org",
      "@type" => "Article",
      "headline" => column.title,
      "description" => column_seo_description(column),
      "datePublished" => column.published_at&.iso8601,
      "dateModified" => column.updated_at&.iso8601,
      "mainEntityOfPage" => {
        "@type" => "WebPage",
        "@id" => page_url
      },
      "author" => {
        "@type" => "Organization",
        "name" => site_name
      },
      "publisher" => {
        "@type" => "Organization",
        "name" => site_name
      }
    }
    data["image"] = [image] if image.present?
    data.compact.to_json
  end

  def public_absolute_url(path)
    host = (respond_to?(:public_request_host) && public_request_host.presence) || request.host
    proto = request.headers["X-Forwarded-Proto"].presence || request.scheme
    normalized = path.to_s.start_with?("/") ? path.to_s : "/#{path}"
    "#{proto}://#{host}#{normalized}"
  end

  def public_related_column_path(column)
    return "#" unless column&.code.present?

    platform_host? ? public_column_show_path(column) : "/columns/#{column.code}"
  end

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
