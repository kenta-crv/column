# frozen_string_literal: true

module TrialNurture
  class ProgressTracker
    def self.ensure_progress(client)
      return if client.blank?

      progress = ClientTrialProgress.find_or_create_by!(client_id: client.id)
      progress.sync_from_client!
      progress
    rescue ActiveRecord::RecordNotUnique
      ClientTrialProgress.find_by!(client_id: client.id).tap(&:sync_from_client!)
    end

    def self.mark_genre!(client)
      ensure_progress(client)&.mark_genre_setup!
    end

    def self.mark_title_suggestion!(client)
      ensure_progress(client)&.mark_title_suggestion!
    end

    def self.mark_pillar_created!(client)
      ensure_progress(client)&.mark_pillar_created!
    end

    def self.mark_pillar_body_completed!(client)
      ensure_progress(client)&.mark_pillar_body_completed!
    end

    def self.mark_child_created!(client)
      ensure_progress(client)&.mark_child_created!
    end

    def self.mark_converted!(client)
      ensure_progress(client)&.mark_converted!
    end
  end
end
