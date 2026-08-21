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

  test "english_article? is false when language is missing or not selected" do
    column = Column.create!(title: "Language fallback", article_type: "pillar", genre: "other", status: "draft", language: "en")
    loaded = Column.select(:id, :code).find(column.id)

    refute loaded.has_attribute?(:language)
    refute loaded.english_article?
    refute Column.new.english_article?
    assert Column.new(language: "en").english_article?
  end

  test "generated_body? uses body_present from list attributes without loading body" do
    client = create_trial_client
    with_body = client.columns.create!(title: "With body", article_type: "cluster", genre: "other", status: "draft", body: "# Hello")
    without_body = client.columns.create!(title: "Without body", article_type: "cluster", genre: "other", status: "draft", body: nil)

    listed = Column.where(id: [with_body.id, without_body.id]).with_list_attributes.index_by(&:id)

    assert_equal true, listed[with_body.id].generated_body?
    assert_equal false, listed[without_body.id].generated_body?
    assert_equal false, listed[with_body.id].has_attribute?(:body)
  end
end
