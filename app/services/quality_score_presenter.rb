class QualityScorePresenter
  AXIS_LABELS = {
    "structure"   => "構成",
    "seo"         => "SEO",
    "readability" => "読みやすさ",
    "usefulness"  => "有用性",
    "originality" => "独自性"
  }.freeze

  class << self
    def normalize_metrics(raw)
      data = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
      axes = (data["axes"] || {}).transform_keys(&:to_s)
      {
        "feedback" => data["feedback"].to_s.presence,
        "axes"     => axes
      }
    end

    def scored?(score)
      score.present? && score.to_f.positive?
    end

    def level_class(score)
      value = score.to_f
      return "score-none" unless value.positive?

      if value >= 80.0
        "score-high"
      elsif value >= 60.0
        "score-mid"
      else
        "score-low"
      end
    end

    def tooltip_lines(score, raw_metrics)
      return [] unless scored?(score)

      metrics = normalize_metrics(raw_metrics)
      lines = ["総合: #{score.to_f.round(1)}点"]

      AXIS_LABELS.each do |key, label|
        axis = metrics["axes"][key]
        next unless axis.is_a?(Hash)

        axis_score = axis["score"]
        axis_note  = axis["note"].to_s.strip
        next if axis_score.blank?

        line = "#{label}: #{axis_score.to_i}/20"
        line += " — #{axis_note}" if axis_note.present?
        lines << line
      end

      feedback = metrics["feedback"]
      lines << feedback if feedback.present?
      lines
    end

    def tooltip_text(score, raw_metrics)
      tooltip_lines(score, raw_metrics).join("\n")
    end
  end
end
