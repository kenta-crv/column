# frozen_string_literal: true

class ClientTrialProgress < ApplicationRecord
  belongs_to :client

  CONVERSION_OFFER_GRACE_DAYS = 3

  STAGES = %i[
    registered
    genre
    title
    pillar
    pillar_body
    child
    converted
  ].freeze

  validates :client_id, uniqueness: true

  def conversion_offer_active?(at: Time.current)
    return false if converted_at.present?

    ends = client.trial_ends_at
    return false if ends.blank?

    window_start = ends - CONVERSION_OFFER_GRACE_DAYS.days
    window_end = ends + CONVERSION_OFFER_GRACE_DAYS.days
    at >= window_start && at < window_end
  end

  def stage
    return :converted if converted_at.present? || paid_plan?
    return :child if first_child_created_at.present?
    return :pillar_body if first_pillar_body_completed_at.present?
    return :pillar if first_pillar_created_at.present?
    return :title if first_title_suggestion_at.present?
    return :genre if genre_setup_at.present?

    :registered
  end

  def not_started?
    stage == :registered
  end

  def has_pillar?
    first_pillar_created_at.present? || first_pillar_body_completed_at.present?
  end

  def has_child?
    first_child_created_at.present?
  end

  def sync_from_client!(at: Time.current)
    attrs = {}
    attrs[:genre_setup_at] = earliest_genre_at if genre_setup_at.blank? && client.service_genres.exists?
    attrs[:first_title_suggestion_at] = at if first_title_suggestion_at.blank? && title_suggestion_used?
    attrs[:first_pillar_created_at] = earliest_pillar_created_at if first_pillar_created_at.blank? && pillar_exists?
    attrs[:first_pillar_body_completed_at] = earliest_pillar_body_completed_at if first_pillar_body_completed_at.blank? && pillar_body_completed?
    attrs[:first_child_created_at] = earliest_child_created_at if first_child_created_at.blank? && child_exists?
    attrs[:converted_at] = at if converted_at.blank? && paid_plan?
    attrs[:conversion_offer_expires_at] = default_offer_expires_at if conversion_offer_expires_at.blank? && default_offer_expires_at.present?

    update!(attrs) if attrs.any?
    self
  end

  def mark_genre_setup!(at: Time.current)
    update!(genre_setup_at: at) if genre_setup_at.blank?
  end

  def mark_title_suggestion!(at: Time.current)
    update!(first_title_suggestion_at: at) if first_title_suggestion_at.blank?
  end

  def mark_pillar_created!(at: Time.current)
    update!(first_pillar_created_at: at) if first_pillar_created_at.blank?
  end

  def mark_pillar_body_completed!(at: Time.current)
    update!(first_pillar_body_completed_at: at) if first_pillar_body_completed_at.blank?
  end

  def mark_child_created!(at: Time.current)
    update!(first_child_created_at: at) if first_child_created_at.blank?
  end

  def mark_converted!(at: Time.current)
    update!(converted_at: at) if converted_at.blank?
  end

  def ensure_conversion_offer_expires_at!
    return if conversion_offer_expires_at.present?
    return if default_offer_expires_at.blank?

    update!(conversion_offer_expires_at: default_offer_expires_at)
  end

  private

  def paid_plan?
    plan = client.subscription_plan.to_s
    plan.present? && plan != "trial"
  end

  def default_offer_expires_at
    ends = client.trial_ends_at
    return if ends.blank?

    ends + CONVERSION_OFFER_GRACE_DAYS.days
  end

  def title_suggestion_used?
    client.client_usage_logs.sum(:title_suggestion_count).positive?
  end

  def pillar_exists?
    client.columns.pillars.exists?
  end

  def child_exists?
    client.columns.where(article_type: Client::CHILD_ARTICLE_TYPES).exists? ||
      client.columns.where.not(parent_id: nil).exists?
  end

  def pillar_body_completed?
    client.columns.pillars.where(generation_status: "completed").exists? ||
      client.columns.pillars.where.not(body: [nil, ""]).exists?
  end

  def earliest_genre_at
    client.service_genres.minimum(:created_at)
  end

  def earliest_pillar_created_at
    client.columns.pillars.minimum(:created_at)
  end

  def earliest_pillar_body_completed_at
    client.columns.pillars.where(generation_status: "completed").minimum(:updated_at) ||
      client.columns.pillars.where.not(body: [nil, ""]).minimum(:updated_at)
  end

  def earliest_child_created_at
    child_scope = client.columns.where(article_type: Client::CHILD_ARTICLE_TYPES)
      .or(client.columns.where.not(parent_id: nil))
    child_scope.minimum(:created_at)
  end
end
