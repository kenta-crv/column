module SeoCheckersHelper
  def seo_checker_path_for_locale
    if params[:locale].present?
      localized_seo_checker_path(locale: params[:locale])
    else
      seo_checker_path
    end
  end

  def seo_checker_submit_path_for_locale
    seo_checker_path_for_locale
  end

  def seo_score_level(score)
    value = score.to_i
    if value >= 80
      "is-high"
    elsif value >= 60
      "is-mid"
    else
      "is-low"
    end
  end
end
