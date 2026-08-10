require "test_helper"

class ColumnsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def create_admin!
    Admin.create!(
      email: "admin-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
  end

  def create_client!(suffix:)
    Client.create!(
      email: "client-#{suffix}-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "Client #{suffix}",
      subscription_plan: "business",
      subscription_status: "active"
    )
  end

  test "admin pillar manage index lists pillars across genres on platform host" do
    admin = create_admin!
    drafity_client = create_client!(suffix: "drafity")
    other_client = create_client!(suffix: "other")

    drafity_pillar = drafity_client.columns.create!(
      title: "Drafity Pillar",
      article_type: "pillar",
      genre: CrawlPolicy::GENRE_KEY,
      status: "draft",
      code: "drafity-pillar-#{SecureRandom.hex(3)}"
    )
    other_pillar = other_client.columns.create!(
      title: "Other Client Pillar",
      article_type: "pillar",
      genre: "security",
      status: "draft",
      code: "other-pillar-#{SecureRandom.hex(3)}"
    )

    host! "drafity.pro"
    sign_in admin

    get columns_path(article_type: "pillar")
    assert_response :success
    assert_includes response.body, drafity_pillar.title
    assert_includes response.body, other_pillar.title
  end
end
