# frozen_string_literal: true

require "test_helper"

class GenreRegistryAliasTest < ActiveSupport::TestCase
  setup do
    GenreRegistry.reset!
  end

  teardown do
    GenreRegistry.reset!
  end

  test "resolve_key normalizes legacy meetia to ai_sales_agent" do
    assert_equal "ai_sales_agent", GenreRegistry.resolve_key("meetia")
    assert_equal "ai_sales_agent", GenreRegistry.resolve_key("ai_sales_agent")
  end

  test "custom genre cannot use alias key meetia" do
    client = Client.new(allowed_genres: [])
    assert_not GenreRegistry.custom_genre_key_allowed_for_client?("meetia", client: client)
  end

  test "canonical_key maps legacy meetia to ai_sales_agent" do
    assert_equal "ai_sales_agent", GenreRegistry.canonical_key("meetia")
    assert_equal "ai_sales_agent", GenreRegistry.canonical_key("ai_sales_agent")
  end

  test "equivalent_keys includes both keys" do
    keys = GenreRegistry.equivalent_keys("ai_sales_agent")
    assert_includes keys, "ai_sales_agent"
    assert_includes keys, "meetia"
  end

  test "genre_entry resolves legacy meetia key" do
    entry = GenreRegistry.genre_entry("meetia")
    assert_equal "Meetia", entry[:service_name]
    assert_equal "AI商談代行", entry[:ja]
  end

  test "genres registry does not expose both meetia and ai_sales_agent" do
    genres = GenreRegistry.genres
    assert genres.key?(:ai_sales_agent)
    assert_not genres.key?(:meetia)
  end
end
