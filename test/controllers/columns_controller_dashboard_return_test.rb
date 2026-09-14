require "test_helper"

class ColumnsControllerDashboardReturnTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "drafity.pro"
    @admin = Admin.create!(
      email: "admin-return-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    sign_in @admin
    @dashboard_filter = dashboard_columns_path(genre: "ai_article_generation", scope: "pillar")
  end

  def create_column!(**attrs)
    Column.create!(
      {
        title: "Return path pillar",
        article_type: "pillar",
        genre: "ai_article_generation",
        status: "draft",
        code: "return-pillar-#{SecureRandom.hex(3)}"
      }.merge(attrs)
    )
  end

  test "dashboard genre pillar filter is manage view not public columns" do
    create_column!
    get @dashboard_filter
    assert_response :success
    assert_includes response.body, "admin-sidebar"
    assert_includes response.body, CGI.escapeHTML(@dashboard_filter)
    assert_includes response.body, "return_to="
    assert_not_includes response.body, "columns-index-page"
  end

  test "destroy from dashboard filter returns to that dashboard" do
    column = create_column!
    assert_difference("Column.count", -1) do
      delete column_path(column), params: { return_to: @dashboard_filter }
    end
    assert_redirected_to @dashboard_filter
  end

  test "destroy without return_to does not go to public columns index" do
    column = create_column!
    delete column_path(column)
    assert_redirected_to dashboard_root_path
    follow_redirect!
    assert_response :success
    assert_includes response.body, "admin-sidebar"
  end

  test "destroy rejects public columns return_to" do
    column = create_column!
    delete column_path(column), params: { return_to: columns_index_path(genre: "ai_article_generation") }
    assert_redirected_to dashboard_root_path
  end

  test "bulk delete from dashboard filter returns to that dashboard" do
    column = create_column!
    assert_difference("Column.count", -1) do
      post bulk_update_drafts_columns_path, params: {
        column_ids: [column.id],
        action_type: "delete_bulk",
        return_to: @dashboard_filter
      }
    end
    assert_redirected_to @dashboard_filter
  end

  test "publish from dashboard filter returns to that dashboard" do
    column = create_column!(
      body: "# 本文\n\n公開できる本文です。",
      status: "completed"
    )
    patch publish_column_path(column), params: { return_to: @dashboard_filter }
    assert_redirected_to @dashboard_filter
    assert column.reload.published?
  end

  test "update from dashboard filter returns to that dashboard" do
    column = create_column!
    patch column_path(column), params: {
      return_to: @dashboard_filter,
      column: { title: "Updated title", genre: column.genre, article_type: "pillar" }
    }
    assert_redirected_to @dashboard_filter
    assert_equal "Updated title", column.reload.title
  end

  test "signed-in english public index remains public view" do
    get localized_columns_index_path(locale: :en, genre: CrawlPolicy::GENRE_KEY)
    assert_response :success
    assert_not_includes response.body, "admin-sidebar"
    assert_not_includes response.body, "Dashboardに戻る"
  end
end
