# frozen_string_literal: true

class DispatchTrialNurtureEmailsJob < ApplicationJob
  queue_as :default

  def perform
    result = TrialNurture::Dispatcher.run!
    Rails.logger.info(
      "[DispatchTrialNurtureEmailsJob] examined=#{result.examined} sent=#{result.sent} skipped=#{result.skipped}"
    )
    result
  end
end
