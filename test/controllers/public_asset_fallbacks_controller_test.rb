# frozen_string_literal: true

require "test_helper"

class PublicAssetFallbacksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @assets_dir = Rails.root.join("public/assets")
    @assets_ok_dir = Rails.root.join("public/assets_ok")
    FileUtils.mkdir_p(@assets_dir)
    FileUtils.mkdir_p(@assets_ok_dir)
    @legacy_css = @assets_dir.join("fallback-test-asset.css")
    @legacy_js = @assets_dir.join("fallback-test-asset.js")
    @prefixed_css = @assets_ok_dir.join("fallback-test-asset.css")
    File.write(@legacy_css, "body{color:#123456}")
    File.write(@legacy_js, "console.log('ok')")
  end

  teardown do
    FileUtils.rm_f(@legacy_css)
    FileUtils.rm_f(@legacy_js)
    FileUtils.rm_f(@prefixed_css)
  end

  test "serves the compiled stylesheet from public/assets at /assets_ok" do
    get "/assets_ok/fallback-test-asset.css"

    assert_response :success
    assert_equal "text/css", response.media_type
    assert_equal "body{color:#123456}", response.body
  end

  test "prefers the file already compiled under public/assets_ok" do
    File.write(@prefixed_css, "body{color:#abcdef}")

    get "/assets_ok/fallback-test-asset.css"

    assert_response :success
    assert_equal "body{color:#abcdef}", response.body
  end

  test "serves javascript from another site origin" do
    get "/assets_ok/fallback-test-asset.js", headers: { "Origin" => "https://j-work.jp" }

    assert_response :success
    assert_equal "text/javascript", response.media_type
    assert_equal "console.log('ok')", response.body
  end

  test "missing asset is not found" do
    get "/assets_ok/missing-fallback-asset.css"

    assert_response :not_found
  end

  test "path traversal is not found" do
    get "/assets_ok/../../config/database.yml"

    assert_response :not_found
  end
end
