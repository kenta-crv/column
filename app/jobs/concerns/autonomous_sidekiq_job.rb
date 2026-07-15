module AutonomousSidekiqJob
  extend ActiveSupport::Concern

  included do
    self.queue_adapter = :sidekiq
    queue_as :autonomous
  end
end
