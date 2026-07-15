require "test_helper"

class ColumnTest < ActiveSupport::TestCase
  def create_trial_client
    Client.create!(
      email: "trial-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "Trial User"
    )
  end

  test "cannot change article type to pillar when pillar limit reached" do
    client = create_trial_client
    client.columns.create!(title: "Existing pillar", article_type: "pillar", genre: "other", status: "draft")

    cluster = client.columns.create!(title: "Cluster draft", article_type: "cluster", genre: "other", status: "draft")
    cluster.article_type = "pillar"

    assert_not cluster.valid?
    assert_includes cluster.errors.full_messages.join, "親記事の作成上限"
  end
end
