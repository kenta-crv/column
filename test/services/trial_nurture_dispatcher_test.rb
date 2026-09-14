# frozen_string_literal: true

require "test_helper"

class TrialNurtureDispatcherTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    ActionMailer::Base.deliveries.clear
  end

  def create_trial_client(email: nil, created_at: 1.day.ago, trial_ends_at: nil)
    client = Client.create!(
      email: email || "trial-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "Trial User"
    )
    ends = trial_ends_at || (created_at + Subscription::TRIAL_DAYS.days)
    client.update_columns(created_at: created_at, trial_ends_at: ends)
    client.subscriptions.where(plan_type: :trial).update_all(trial_ends_at: ends, created_at: created_at)
    client.reload
  end

  test "day1 sends once for not started and does not resend" do
    client = create_trial_client(created_at: 1.day.ago)

    assert_emails 1 do
      TrialNurture::Dispatcher.run!(now: Time.current)
    end
    assert_equal "day1_not_started", TrialNurtureEmailLog.find_by!(client: client).kind

    assert_emails 0 do
      TrialNurture::Dispatcher.run!(now: Time.current)
    end
  end

  test "still not started on day5 gets a different follow-up email" do
    client = create_trial_client(created_at: 5.days.ago)
    TrialNurtureEmailLog.create!(
      client: client,
      kind: "day1_not_started",
      sent_at: 4.days.ago,
      stage_at_send: "registered"
    )

    assert_emails 1 do
      TrialNurture::Dispatcher.run!(now: Time.current)
    end
    assert TrialNurtureEmailLog.exists?(client: client, kind: "day5_not_started")
  end

  test "day11 conversion offer uses intro 15 percent metadata" do
    started = 11.days.ago
    client = create_trial_client(created_at: started, trial_ends_at: started + Subscription::TRIAL_DAYS.days)
    ServiceGenre.create!(
      client: client,
      key: "demo_genre_#{SecureRandom.hex(3)}",
      ja: "デモ",
      sub_categories: {}
    )

    assert_emails 1 do
      TrialNurture::Dispatcher.run!(now: Time.current)
    end

    log = TrialNurtureEmailLog.find_by!(client: client, kind: "day11_conversion_offer")
    progress = client.client_trial_progress
    assert progress.conversion_offer_expires_at.present?
    assert_equal Subscription::STANDARD_INTRO_PERCENT_OFF, log.metadata["offer_percent_off"].to_i
    assert_equal 15, Subscription::TRIAL_CONVERSION_PERCENT_OFF
    assert_equal progress.conversion_offer_expires_at.to_i, Time.zone.parse(log.metadata["offer_expires_at"].to_s).to_i
  end

  test "progress sync marks genre from service genre create" do
    client = create_trial_client
    ServiceGenre.create!(
      client: client,
      key: "sync_genre_#{SecureRandom.hex(3)}",
      ja: "同期",
      sub_categories: {}
    )
    progress = client.reload.client_trial_progress
    assert progress.present?
    assert progress.genre_setup_at.present?
    assert_equal :genre, progress.stage
  end

  test "paid clients are skipped" do
    client = create_trial_client(created_at: 1.day.ago)
    client.update_columns(subscription_plan: "standard", subscription_status: "active")

    assert_emails 0 do
      TrialNurture::Dispatcher.run!(now: Time.current)
    end
  end
end
