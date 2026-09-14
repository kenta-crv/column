# frozen_string_literal: true

require "test_helper"

class Dashboard::TrialProgressTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def create_trial_client!(company:)
    Client.create!(
      email: "trial-client-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      password_confirmation: "password",
      company: company,
      preferred_locale: "ja"
    )
  end

  setup do
    @admin = Admin.create!(
      email: "trial-admin-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      password_confirmation: "password"
    )
  end

  test "admin page shows milestones recorded by real callbacks" do
    client = create_trial_client!(company: "Trial Progress Co")
    ServiceGenre.create!(
      client: client,
      key: "admin_genre_#{SecureRandom.hex(3)}",
      ja: "管理確認",
      sub_categories: {}
    )
    client.record_title_suggestion!
    pillar = client.columns.create!(
      title: "Admin pillar",
      article_type: "pillar",
      genre: "other",
      status: "draft"
    )
    pillar.update!(body: "<p>本文</p>", generation_status: "completed", status: "completed")
    GenerateColumnBodyJob.new.send(:mark_trial_pillar_body_completed!, pillar.reload)
    client.columns.create!(
      title: "Admin child",
      article_type: "cluster",
      genre: "other",
      status: "draft",
      parent: pillar
    )
    TrialNurtureEmailLog.create!(
      client: client,
      kind: "day5_no_child",
      sent_at: 1.day.ago,
      stage_at_send: "pillar_body"
    )

    sign_in @admin
    get dashboard_trial_progress_path

    assert_response :success
    assert_includes @response.body, "Trial Progress Co"
    assert_includes @response.body, "子記事着手済"
    assert_includes @response.body, "day5_no_child"
    assert_select "a[href=?]", dashboard_trial_progress_path, text: /トライアル着手ログ|Trial progress/
  end

  test "signup-only client appears as not started on admin page" do
    create_trial_client!(company: "Not Started Co")

    sign_in @admin
    get dashboard_trial_progress_path

    assert_response :success
    assert_includes @response.body, "Not Started Co"
    assert_includes @response.body, "登録のみ（未着手）"
  end

  test "client cannot open trial progress" do
    client = create_trial_client!(company: "Blocked Co")
    sign_in client
    get dashboard_trial_progress_path
    assert_response :redirect
  end
end
