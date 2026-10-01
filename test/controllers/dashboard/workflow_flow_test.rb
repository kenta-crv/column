# frozen_string_literal: true

require "test_helper"

class Dashboard::WorkflowFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "drafity.pro"
  end

  def create_trial_client!(preferred_locale: "ja")
    Client.create!(
      email: "workflow-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "Workflow Client",
      subscription_plan: "trial",
      subscription_status: "trialing",
      trial_ends_at: 14.days.from_now,
      preferred_locale: preferred_locale
    )
  end

  test "dashboard next action asks for related titles after the first article body exists" do
    client = create_trial_client!
    complete_client_first_run!(client)
    pillar = client.columns.pillars.order(:id).last
    sign_in client

    get dashboard_root_path
    assert_response :success
    assert_includes response.body, "次にやること"
    assert_includes response.body, "関連記事のタイトルを作ります"
    assert_select "a.dashboard-flow__cta[href=?]", column_path(pillar, anchor: "related-articles"), text: "関連記事のタイトルを作る"
    assert_not_includes response.body, "ジャンル・サービス"
    assert_not_includes response.body, "親の管理画面から子タイトル"
  end

  test "dashboard next action asks to generate related bodies after child titles exist" do
    client = create_trial_client!
    complete_client_first_run!(client)
    pillar = client.columns.pillars.order(:id).last
    previous = Thread.current[:column_skip_client_plan_limits]
    Thread.current[:column_skip_client_plan_limits] = true
    client.columns.create!(
      title: "Related title",
      article_type: "child",
      parent_id: pillar.id,
      genre: pillar.genre,
      status: "draft",
      language: "ja"
    )
    Thread.current[:column_skip_client_plan_limits] = previous
    sign_in client

    get dashboard_root_path
    assert_response :success
    assert_includes response.body, "関連記事のタイトルができました"
    assert_select "a.dashboard-flow__cta[href=?]", column_path(pillar, anchor: "related-articles"), text: "関連記事の本文を作る"
  end

  test "english dashboard next action stays in english" do
    client = create_trial_client!(preferred_locale: "en")
    complete_client_first_run!(client)
    sign_in client

    get dashboard_root_path
    assert_response :success
    assert_includes response.body, "Next step"
    assert_includes response.body, "Create related titles"
    assert_not_includes response.body, "次にやること"
    assert_not_includes response.body, "ジャンル・サービス"
  end

  test "admin dashboard does not show the client next-action card" do
    admin = Admin.create!(email: "workflow-admin-#{SecureRandom.hex(4)}@example.com", password: "password123")
    sign_in admin

    get dashboard_root_path
    assert_response :success
    assert_not_includes response.body, "次にやること"
    assert_not_includes response.body, "ジャンル・サービス"
  end
end
