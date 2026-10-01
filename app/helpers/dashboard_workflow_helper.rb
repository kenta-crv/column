# frozen_string_literal: true

module DashboardWorkflowHelper
  PROGRESS_KEYS = %i[first_article related_titles related_bodies].freeze

  def dashboard_next_action
    return unless client_signed_in? && !acting_as_admin?

    client = current_client
    pillars = client.columns.pillars.with_list_attributes.order(:id).to_a
    if pillars.empty?
      return dashboard_next_action_payload(:need_service) if client.service_genres.none?

      return dashboard_next_action_payload(:need_article)
    end

    parent_ids = pillars.map(&:id)
    child_counts = client.columns.where(parent_id: parent_ids).group(:parent_id).count
    child_body_counts = client.columns.where(parent_id: parent_ids).merge(Column.with_generated_body).group(:parent_id).count
    progress = {
      first_article: pillars.any?(&:generated_body?),
      related_titles: child_counts.values.any?(&:positive?),
      related_bodies: child_body_counts.values.any?(&:positive?)
    }

    generating = pillars.find { |pillar| %w[queued generating].include?(pillar.generation_status.to_s) && !pillar.generated_body? }
    return dashboard_next_action_payload(:generating, pillar: generating, progress: progress) if generating

    failed = pillars.find { |pillar| pillar.generation_status.to_s == "failed" && !pillar.generated_body? }
    return dashboard_next_action_payload(:failed, pillar: failed, progress: progress) if failed

    need_body = pillars.find { |pillar| !pillar.generated_body? }
    return dashboard_next_action_payload(:need_body, pillar: need_body, progress: progress) if need_body

    need_titles = pillars.find { |pillar| pillar.generated_body? && child_counts[pillar.id].to_i.zero? }
    return dashboard_next_action_payload(:need_related_titles, pillar: need_titles, progress: progress) if need_titles

    need_bodies = pillars.find do |pillar|
      child_counts[pillar.id].to_i.positive? && child_body_counts[pillar.id].to_i < child_counts[pillar.id].to_i
    end
    return dashboard_next_action_payload(:need_related_bodies, pillar: need_bodies, progress: progress) if need_bodies

    dashboard_next_action_payload(:done, pillar: pillars.last, progress: progress)
  end

  private

  def dashboard_next_action_payload(key, pillar: nil, progress: {})
    {
      key: key,
      lead: t("drafity.dashboard.workflow.#{key}.lead"),
      cta: t("drafity.dashboard.workflow.#{key}.cta"),
      path: dashboard_next_action_path(key, pillar),
      article_title: pillar&.title,
      progress: progress,
      current: dashboard_next_action_current(key)
    }
  end

  def dashboard_next_action_current(key)
    case key
    when :need_related_titles then :related_titles
    when :need_related_bodies then :related_bodies
    when :done then nil
    else :first_article
    end
  end

  def dashboard_next_action_path(key, pillar)
    case key
    when :need_service
      dashboard_service_genres_path
    when :need_article, :done
      new_column_path
    when :need_body
      dashboard_columns_path(scope: "pillar")
    when :need_related_titles, :need_related_bodies
      column_path(pillar, anchor: "related-articles")
    else
      column_path(pillar)
    end
  end
end
