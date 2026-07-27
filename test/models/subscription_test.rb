require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  def create_client
    Client.create!(
      email: "subscription-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "Subscription User"
    )
  end

  test "handles missing plan_type without raising" do
    client = create_client
    subscription = Subscription.new(client: client, status: :active)

    assert_equal "不明", subscription.plan_name
    assert_equal "不明", subscription.display_name
    assert_equal 0, subscription.price
    assert_equal [], subscription.feature_list
    assert_equal Subscription::PLANS[:trial], Subscription.config_for(nil)
    assert_equal Subscription::PLANS[:trial], Subscription.limits_for(nil)
  end

  test "treats unknown raw plan_type safely" do
    client = create_client
    subscription = Subscription.new(client: client, status: :active)
    subscription[:plan_type] = "legacy"

    assert_equal "legacy", subscription.plan_name
    assert_equal "legacy", subscription.display_name
    assert_equal 0, subscription.price
    assert_equal [], subscription.feature_list
  end
end
