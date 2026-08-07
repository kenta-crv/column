# frozen_string_literal: true

require "test_helper"

class AttributionPolicyTest < ActiveSupport::TestCase
  def create_client(plan_type:)
    client = Client.create!(
      email: "attribution-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "Attribution User"
    )
    client.subscriptions.where(status: :active).update_all(status: :cancelled)
    client.subscriptions.create!(plan_type: plan_type, status: :active)
    client.update!(subscription_plan: plan_type.to_s, subscription_status: "active")
    client
  end

  test "standard and below require attribution" do
    %i[trial starter standard].each do |plan|
      client = create_client(plan_type: plan)
      assert AttributionPolicy.required?(client: client), "#{plan} should require attribution"
      assert client.attribution_required?
    end
  end

  test "business and enterprise do not require attribution" do
    %i[business enterprise].each do |plan|
      client = create_client(plan_type: plan)
      assert_not AttributionPolicy.required?(client: client), "#{plan} should not require attribution"
      assert_not client.attribution_required?
    end
  end

  test "platform-owned genre is treated like enterprise" do
    ServiceGenre.create!(
      client_id: nil,
      key: "own_platform_genre",
      ja: "自社ジャンル"
    )

    client = create_client(plan_type: :starter)
    assert_not AttributionPolicy.required?(client: client, genre: "own_platform_genre")
    assert_not AttributionPolicy.required?(client: nil, genre: "自社ジャンル")
  end

  test "client-owned genre with same key still follows plan" do
    ServiceGenre.create!(
      client_id: nil,
      key: "shared_key",
      ja: "共有キー"
    )
    client = create_client(plan_type: :starter)
    client.service_genres.create!(key: "shared_key", ja: "顧客ジャンル")

    assert AttributionPolicy.required?(client: client, genre: "shared_key")
  end

  test "column without client is treated like enterprise" do
    client = create_client(plan_type: :starter)
    column = Column.new(client_id: nil, genre: "anything", title: "x")

    assert_not AttributionPolicy.required?(client: client, genre: "anything", column: column)
  end

  test "payload includes visible powered by link" do
    payload = AttributionPolicy.payload(base_url: "https://example.com")
    assert_equal true, payload[:required]
    assert_includes payload[:text], "Drafity"
    assert_includes payload[:html], "drafity-attribution"
    assert_includes payload[:html], "https://"
    assert_not_includes payload[:html], "display:none"
  end
end
