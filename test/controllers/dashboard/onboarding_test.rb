# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class Dashboard::OnboardingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "drafity.pro"
  end

  def create_trial_client!(preferred_locale: "ja", company: nil)
    Client.create!(
      email: "onboard-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "Onboarding Client",
      company: company,
      subscription_plan: "trial",
      subscription_status: "trialing",
      trial_ends_at: 14.days.from_now,
      preferred_locale: preferred_locale
    )
  end

  test "signup lands on first-run wizard without dashboard jargon" do
    email = "onboard-signup-#{SecureRandom.hex(4)}@example.com"
    post "/clients", params: {
      client: {
        email: email,
        password: "password123",
        password_confirmation: "password123"
      }
    }

    assert_redirected_to dashboard_start_path
    follow_redirect!
    assert_response :success
    assert_includes response.body, "3つのステップで最初の記事を作ります"
    assert_includes response.body, "会社名"
    assert_includes response.body, "サービス名"
    assert_not_includes response.body, "親記事の作成開始"
    assert_not_includes response.body, "Meetia"
    assert_not_includes response.body, "キー（英小文字"
    assert_not_includes response.body, "name=\"service_genre[column_cta][title]\""
  end

  test "first-run client is sent from dashboard and columns/new to the wizard" do
    client = create_trial_client!
    sign_in client

    get dashboard_root_path
    assert_redirected_to dashboard_start_path

    get new_column_path
    assert_redirected_to dashboard_start_path

    get new_dashboard_service_genre_path
    assert_redirected_to dashboard_start_path
  end

  test "wizard saves company onto the client for management" do
    client = create_trial_client!
    sign_in client

    post dashboard_start_service_path, params: {
      onboarding: {
        company: "株式会社サンプル",
        service_name: "オンライン英会話",
        strong_points: "初心者でも続けやすい"
      }
    }
    assert_redirected_to dashboard_start_path
    assert_equal "株式会社サンプル", client.reload.company

    genre = client.service_genres.order(:id).last
    assert_equal "オンライン英会話", genre.ja
    assert_equal "オンライン英会話", genre.service_name
    assert genre.key.present?
    assert_match(/\A[a-z0-9_]+\z/, genre.key)
    assert_not_equal "genre", genre.key

    follow_redirect!
    assert_response :success
    assert_includes response.body, "最初の記事タイトルを決める"
    assert_not_includes response.body, "ジャンル"

    sign_out client
    admin = Admin.create!(
      email: "onboard-admin-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    sign_in admin
    get dashboard_management_path
    assert_response :success
    assert_includes response.body, "株式会社サンプル"
  end

  test "title and generate complete first-run and open the dashboard" do
    client = create_trial_client!
    sign_in client

    post dashboard_start_service_path, params: {
      onboarding: {
        company: "株式会社サンプル",
        service_name: "オンライン英会話"
      }
    }
    post dashboard_start_title_path, params: {
      onboarding: {
        title: "初めてのオンライン英会話の始め方",
        language: "ja"
      }
    }
    assert_redirected_to dashboard_start_path
    pillar = client.reload.first_run_pillar
    assert_equal "初めてのオンライン英会話の始め方", pillar.title
    assert_equal client.service_genres.first.key, pillar.genre

    get dashboard_start_path
    assert_response :success
    assert_includes response.body, "通常記事"
    assert_includes response.body, "比較"
    assert_includes response.body, "自社おすすめ"
    assert_select "input[name='onboarding[generation_mode]']", count: 3
    assert_select "input[name='onboarding[generation_mode]'][checked]", count: 0

    post dashboard_start_generate_path
    assert_response :unprocessable_entity
    assert_includes response.body, "記事の書き方を選んでください"

    GenerateColumnBodyJob.stub(:perform_now, ->(*) {}) do
      post dashboard_start_generate_path, params: {
        onboarding: { generation_mode: "comparison" }
      }
    end
    assert_redirected_to dashboard_root_path
    assert_equal "comparison", pillar.reload.generation_mode
    assert_equal "queued", pillar.generation_status
    refute client.reload.first_run?

    follow_redirect!
    assert_response :success
    assert_includes response.body, "親記事の作成開始"
    assert_includes response.body, "記事の生成を開始しました"

    get dashboard_start_path
    assert_redirected_to dashboard_root_path
  end

  test "title suggestion returns one title for the first-run service" do
    client = create_trial_client!
    sign_in client
    post dashboard_start_service_path, params: {
      onboarding: {
        company: "Acme Inc.",
        service_name: "Hair salon"
      }
    }

    follow_redirect!
    assert_response :success
    assert_includes response.body, "data-suggest-url"
    assert_includes response.body, "DrafityOnboardingSuggest"
    assert_includes response.body, "タイトルを提案する"

    PillarTitleSuggestionService.stub(:call, { success: true, titles: ["salon opening guide"] }) do
      get dashboard_start_suggest_path, params: {
        keyword1: "opening",
        keyword2: "price",
        language: "en"
      }, as: :json
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal ["salon opening guide"], json["titles"]
  end

  test "english first-run wizard stays in english" do
    client = create_trial_client!(preferred_locale: "en")
    sign_in client

    get dashboard_start_path
    assert_response :success
    assert_includes response.body, "Create your first article in 3 steps"
    assert_includes response.body, "Company name"
    assert_not_includes response.body, "親記事の作成開始"
    assert_not_includes response.body, "3つのステップで最初の記事を作ります"
  end
end
