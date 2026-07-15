require "test_helper"

class ClientTest < ActiveSupport::TestCase
  def create_trial_client
    Client.create!(
      email: "trial-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "Trial User"
    )
  end

  test "trial client cannot create second pillar slot" do
    client = create_trial_client

    first = client.columns.create!(title: "First pillar", article_type: "pillar", genre: "other", status: "draft")
    assert first.persisted?

    second = client.columns.build(title: "Second pillar", article_type: "pillar", genre: "other", status: "draft")
    assert_not second.valid?
    assert_includes second.errors.full_messages.join, "親記事の作成上限"
  end

  test "blank top-level article counts as pillar slot" do
    client = create_trial_client

    first = client.columns.create!(title: "Blank top-level", genre: "other", status: "draft")
    assert first.persisted?

    second = client.columns.build(title: "Second pillar", article_type: "pillar", genre: "other", status: "draft")
    assert_not second.valid?
  end

  test "child articles do not consume pillar slots" do
    client = create_trial_client

    client.columns.create!(title: "Pillar", article_type: "pillar", genre: "other", status: "draft")

    3.times do |i|
      child = client.columns.create!(
        title: "Child #{i}",
        article_type: "child",
        genre: "other",
        status: "draft"
      )
      assert child.persisted?
    end

    fourth_child = client.columns.build(title: "Child 4", article_type: "child", genre: "other", status: "draft")
    assert_not fourth_child.valid?
  end
end
