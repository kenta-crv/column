class AdvanceAutonomousRunJob < ApplicationJob
  queue_as :article_generation

  def perform(run_id)
    AutonomousContentRun.recover_stale_runs!

    run = AutonomousContentRun.find_by(id: run_id)
    return unless run

    case run.status
    when "queued"
      run.start_pillar_generation!
    end
  end
end
