# frozen_string_literal: true

require "test_helper"

class SeoCheckersControllerTest < ActionDispatch::IntegrationTest
  setup do
    SeoChecker::UsageLimiter.reset!("127.0.0.1")
  end

  teardown do
    SeoChecker::UsageLimiter.reset!("127.0.0.1")
  end

  test "show renders checker form" do
    get seo_checker_path
    assert_response :success
    assert_match(/SEO/, response.body)
  end

  test "create rejects blank url" do
    post seo_checker_path, params: { url: "" }
    assert_response :unprocessable_entity
  end

  test "create analyzes stubbed page and decrements remaining" do
    html = <<~HTML
      <html><head>
        <title>テスト記事タイトルは十分な長さがあります</title>
        <meta name="description" content="これはテスト用のメタディスクリプションで70文字以上になるように調整した説明文です。">
        <meta name="viewport" content="width=device-width">
      </head><body>
        <h1>テスト記事</h1>
        <h2>見出しA</h2><p>#{'本文です。' * 200}</p>
        <h2>見出しB</h2><p>#{'続きです。' * 200}</p>
        <h2>見出しC</h2><p>#{'さらにです。' * 200}</p>
      </body></html>
    HTML

    fake = SeoChecker::PageFetcher::Result.new(
      url: "https://example.com/a",
      final_url: "https://example.com/a",
      body: html,
      status: 200
    )
    SeoChecker::PageFetcher.stub(:fetch, fake) do
      post seo_checker_path, params: { url: "https://example.com/a" }
    end

    assert_response :success
    assert_match(/総合スコア|Overall score/, response.body)
    assert_equal 2, SeoChecker::UsageLimiter.remaining("127.0.0.1")
  end

  test "blocks after daily limit" do
    3.times { SeoChecker::UsageLimiter.consume!("127.0.0.1") }

    post seo_checker_path, params: { url: "https://example.com/a" }
    assert_response :too_many_requests
  end
end
