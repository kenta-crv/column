# frozen_string_literal: true

require "test_helper"

class SeoCheckerUsageLimiterTest < ActiveSupport::TestCase
  setup do
    @ip = "203.0.113.#{rand(1..250)}"
    SeoChecker::UsageLimiter.reset!(@ip)
  end

  teardown do
    SeoChecker::UsageLimiter.reset!(@ip)
  end

  test "allows three uses per day then blocks" do
    assert_equal 3, SeoChecker::UsageLimiter.remaining(@ip)

    3.times do
      assert SeoChecker::UsageLimiter.allowed?(@ip)
      SeoChecker::UsageLimiter.consume!(@ip)
    end

    assert_equal 0, SeoChecker::UsageLimiter.remaining(@ip)
    assert_not SeoChecker::UsageLimiter.allowed?(@ip)
  end
end
