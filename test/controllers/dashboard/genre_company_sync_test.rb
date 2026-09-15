# frozen_string_literal: true

require "test_helper"

class Dashboard::GenreCompanySyncTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "drafity.pro"
  end

  def create_admin!
    Admin.create!(
      email: "admin-company-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
  end

  def create_client!(company: nil)
    Client.create!(
      email: "client-company-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "Company Sync Client",
      company: company,
      subscription_plan: "trial",
      subscription_status: "trialing",
      trial_ends_at: 14.days.from_now,
      preferred_locale: "ja"
    )
  end

  test "client genre create writes company onto the client and management shows it" do
    client = create_client!
    assert_nil client.company.presence

    sign_in client
    post dashboard_start_service_path, params: {
      onboarding: {
        company: "株式会社サンプル",
        service_name: "美容院"
      }
    }
    assert_redirected_to dashboard_start_path
    assert_equal "株式会社サンプル", client.reload.company

    sign_out client
    sign_in create_admin!
    get dashboard_management_path
    assert_response :success
    assert_includes response.body, "株式会社サンプル"
  end

  test "client genre update overwrites the company shown on management" do
    client = create_client!(company: "旧社名")
    sign_in client
    post dashboard_start_service_path, params: {
      onboarding: {
        company: "旧社名",
        service_name: "美容院"
      }
    }
    genre = ServiceGenre.order(:id).last
    complete_client_first_run!(client)

    patch dashboard_service_genre_path(genre), params: {
      service_genre: {
        ja: "美容院",
        company: "新社名株式会社",
        column_cta: { enabled: "1", theme: "#2563eb", title: "案内" }
      }
    }
    assert_redirected_to dashboard_service_genres_path
    assert_equal "新社名株式会社", client.reload.company

    sign_out client
    sign_in create_admin!
    get dashboard_management_path
    assert_response :success
    assert_includes response.body, "新社名株式会社"
    assert_not_includes response.body, "旧社名"
  end

  test "admin genre create assigned to a client writes that client's company" do
    client = create_client!
    admin = create_admin!
    sign_in admin

    post dashboard_service_genres_path, params: {
      service_genre: {
        client_id: client.id,
        key: "salon_#{SecureRandom.hex(3)}",
        ja: "美容院",
        service_name: "美容室",
        company: "株式会社J Work",
        column_cta: { enabled: "1", theme: "default", title: "案内" }
      }
    }
    assert_redirected_to dashboard_service_genres_path
    assert_equal "株式会社J Work", client.reload.company

    get dashboard_management_path
    assert_response :success
    assert_includes response.body, "株式会社J Work"
  end

  test "admin system-shared genre does not write company onto an unrelated client" do
    client = create_client!(company: nil)
    admin = create_admin!
    sign_in admin

    post dashboard_service_genres_path, params: {
      service_genre: {
        client_id: "",
        key: "shared_#{SecureRandom.hex(3)}",
        ja: "共有ジャンル",
        service_name: "共有",
        company: "どこにも載らない社名",
        column_cta: { enabled: "1", theme: "default", title: "案内" }
      }
    }
    assert_redirected_to dashboard_service_genres_path
    assert_nil client.reload.company.presence

    get dashboard_management_path
    assert_response :success
    assert_not_includes response.body, "どこにも載らない社名"
  end
end
