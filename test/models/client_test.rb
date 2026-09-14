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

  test "blank top-level article consumes a child slot by default type" do
    client = create_trial_client

    first = client.columns.create!(title: "Blank top-level", genre: "other", status: "draft")
    assert first.persisted?
    assert_equal "cluster", first.article_type
    assert client.can_create_pillar?

    second = client.columns.build(title: "Second pillar", article_type: "pillar", genre: "other", status: "draft")
    assert second.valid?
  end

  test "child articles do not consume pillar slots" do
    client = create_trial_client

    client.columns.create!(title: "Pillar", article_type: "pillar", genre: "other", status: "draft")

    5.times do |i|
      child = client.columns.create!(
        title: "Child #{i}",
        article_type: "child",
        genre: "other",
        status: "draft"
      )
      assert child.persisted?
    end

    extra_child = client.columns.build(title: "Child extra", article_type: "child", genre: "other", status: "draft")
    assert_not extra_child.valid?
    assert_not client.can_create_pillar?
  end

  test "deleting a pillar does not restore trial creation quota" do
    client = create_trial_client
    first = client.columns.create!(title: "First pillar", article_type: "pillar", genre: "other", status: "draft")
    first.destroy!

    second = client.columns.build(title: "Replacement pillar", article_type: "pillar", genre: "other", status: "draft")
    assert_not second.valid?
    assert_includes second.errors.full_messages.join, "親記事の作成上限"
  end

  test "deleting a child does not restore trial creation quota" do
    client = create_trial_client
    client.columns.create!(title: "Pillar", article_type: "pillar", genre: "other", status: "draft")

    children = 5.times.map do |i|
      client.columns.create!(title: "Child #{i}", article_type: "child", genre: "other", status: "draft")
    end
    children.last.destroy!

    extra = client.columns.build(title: "Replacement child", article_type: "child", genre: "other", status: "draft")
    assert_not extra.valid?
    assert_includes extra.errors.full_messages.join, "子記事の作成上限"
  end

  test "paid plan also keeps quota after article delete in the same period" do
    client = create_trial_client
    client.current_subscription.update!(plan_type: :standard, status: :active)
    client.update!(subscription_plan: "standard", subscription_status: "active")

    limit = client.plan_limits[:pillar_articles]
    created = limit.times.map do |i|
      client.columns.create!(title: "Standard pillar #{i}", article_type: "pillar", genre: "other", status: "draft")
    end
    created.last.destroy!

    extra = client.columns.build(title: "Replacement standard pillar", article_type: "pillar", genre: "other", status: "draft")
    assert_not extra.valid?
    assert_includes extra.errors.full_messages.join, "親記事の作成上限"
  end
end
