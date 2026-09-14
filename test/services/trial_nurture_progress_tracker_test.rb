# frozen_string_literal: true

require "test_helper"

class TrialNurtureProgressTrackerTest < ActiveSupport::TestCase
  def create_trial_client
    Client.create!(
      email: "progress-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "Progress User",
      company: "Progress Co",
      preferred_locale: "ja"
    )
  end

  test "signup creates a registered-only progress row" do
    client = create_trial_client
    progress = client.reload.client_trial_progress

    assert progress.present?
    assert_equal :registered, progress.stage
    assert_nil progress.genre_setup_at
    assert_nil progress.first_title_suggestion_at
    assert_nil progress.first_pillar_created_at
    assert_nil progress.first_pillar_body_completed_at
    assert_nil progress.first_child_created_at
    assert_nil progress.converted_at
  end

  test "real user actions record each milestone once" do
    client = create_trial_client

    ServiceGenre.create!(
      client: client,
      key: "progress_genre_#{SecureRandom.hex(3)}",
      ja: "進捗ジャンル",
      sub_categories: {}
    )
    progress = client.reload.client_trial_progress
    assert progress.genre_setup_at.present?
    assert_equal :genre, progress.stage
    first_genre_at = progress.genre_setup_at

    client.record_title_suggestion!
    progress.reload
    assert progress.first_title_suggestion_at.present?
    assert_equal :title, progress.stage
    first_title_at = progress.first_title_suggestion_at

    pillar = client.columns.create!(
      title: "Progress pillar",
      article_type: "pillar",
      genre: "other",
      status: "draft"
    )
    progress.reload
    assert progress.first_pillar_created_at.present?
    assert_equal :pillar, progress.stage
    first_pillar_at = progress.first_pillar_created_at

    pillar.update!(body: "<p>生成本文</p>", generation_status: "completed", status: "completed")
    GenerateColumnBodyJob.new.send(:mark_trial_pillar_body_completed!, pillar.reload)
    progress.reload
    assert progress.first_pillar_body_completed_at.present?
    assert_equal :pillar_body, progress.stage
    first_body_at = progress.first_pillar_body_completed_at

    client.columns.create!(
      title: "Progress child",
      article_type: "cluster",
      genre: "other",
      status: "draft",
      parent: pillar
    )
    progress.reload
    assert progress.first_child_created_at.present?
    assert_equal :child, progress.stage
    first_child_at = progress.first_child_created_at

    TrialNurture::ProgressTracker.mark_converted!(client)
    progress.reload
    assert progress.converted_at.present?
    assert_equal :converted, progress.stage
    first_converted_at = progress.converted_at

    TrialNurture::ProgressTracker.mark_genre!(client)
    TrialNurture::ProgressTracker.mark_title_suggestion!(client)
    TrialNurture::ProgressTracker.mark_pillar_created!(client)
    TrialNurture::ProgressTracker.mark_pillar_body_completed!(client)
    TrialNurture::ProgressTracker.mark_child_created!(client)
    TrialNurture::ProgressTracker.mark_converted!(client)
    progress.reload

    assert_equal first_genre_at.to_i, progress.genre_setup_at.to_i
    assert_equal first_title_at.to_i, progress.first_title_suggestion_at.to_i
    assert_equal first_pillar_at.to_i, progress.first_pillar_created_at.to_i
    assert_equal first_body_at.to_i, progress.first_pillar_body_completed_at.to_i
    assert_equal first_child_at.to_i, progress.first_child_created_at.to_i
    assert_equal first_converted_at.to_i, progress.converted_at.to_i
  end
end
