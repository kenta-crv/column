ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

class ActiveSupport::TestCase
  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Add more helper methods to be used by all tests here...
end

class ActionDispatch::IntegrationTest
  def complete_client_first_run!(client)
    previous = Thread.current[:column_skip_client_plan_limits]
    Thread.current[:column_skip_client_plan_limits] = true
    client.columns.create!(
      title: "First generated pillar",
      article_type: "pillar",
      genre: client.service_genres.order(:id).first&.key.presence || "other",
      status: "completed",
      generation_status: "completed",
      body: "<p>初回フロー完了用の本文です。十分な長さの本文。</p>",
      language: client.preferred_locale.to_s.start_with?("en") ? "en" : "ja"
    )
  ensure
    Thread.current[:column_skip_client_plan_limits] = previous
  end
end
