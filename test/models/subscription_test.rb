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

  test "bootstraps trial subscription on client create" do
    client = create_client
    assert_equal "trial", client.subscription_plan
    assert_equal "active", client.subscription_status
    assert client.trial_ends_at.present?
    assert_equal 1, client.subscriptions.where(plan_type: :trial, status: :active).count
  end

  test "catalog prices and trial limits" do
    assert_equal 49_800, Subscription.price_for(:standard, currency: :jpy)
    assert_equal 349, Subscription.price_for(:standard, currency: :usd)
    assert_equal 98_000, Subscription.price_for(:business, currency: :jpy)
    assert_equal 198_000, Subscription.price_for(:enterprise, currency: :jpy)

    trial = Subscription.limits_for(:trial)
    assert_equal 1, trial[:pillar_articles]
    assert_equal 5, trial[:child_articles]
    assert_equal 8, trial[:image_generations]
    assert_equal 3, trial[:title_suggestions]
    assert_equal false, trial[:api_enabled]
    assert_equal false, trial[:ai_autonomous]
    assert_equal true, trial[:attribution_required]

    assert_equal false, Subscription::PLANS[:starter][:show_on_lp]
    assert_equal false, Subscription::PLANS[:starter][:checkout_selectable]
    assert Subscription.purchasable_plans.key?(:standard)
    refute Subscription.purchasable_plans.key?(:starter)
  end

  test "expire trial without charge" do
    client = create_client
    sub = client.subscriptions.find_by!(plan_type: :trial)
    sub.update!(trial_ends_at: 1.hour.ago)
    client.update_columns(trial_ends_at: 1.hour.ago)

    sub.expire_trial_without_charge!
    assert_equal "expired", sub.reload.status
    assert_equal "expired", client.reload.subscription_status
  end
end
