# frozen_string_literal: true

class TrialNurtureEmailLog < ApplicationRecord
  belongs_to :client

  KINDS = %w[
    day1_not_started
    day5_not_started
    day5_no_pillar
    day5_no_child
    day11_conversion_offer
    day15_expired_followup
  ].freeze

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :sent_at, presence: true
  validates :kind, uniqueness: { scope: :client_id }
end
