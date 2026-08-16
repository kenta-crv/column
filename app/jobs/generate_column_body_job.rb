require_dependency "flux_image_generator_service"

class GenerateColumnBodyJob < ApplicationJob
  queue_as :article_generation

  def self.perform_later_for_autonomous(column_id, autonomous_run_id:)
    set(queue_adapter: :sidekiq, queue_name: "autonomous")
      .perform_later(column_id, autonomous_run_id: autonomous_run_id)
  end

  retry_on Net::ReadTimeout, wait: :exponentially_longer, attempts: 3

  class StopRequested < StandardError; end

  def perform(column_id, autonomous_run_id: nil)
    AutonomousContentRun.recover_stale_runs! if autonomous_run_id.present?

    column = Column.find_by(id: column_id)
    return unless column

    if column.article_type == "pillar" && column.body.present?
      ensure_column_image!(column)
      run_quality_evaluation!(column.id) unless quality_score_present?(column)
      if autonomous_run_id.present?
        AutonomousContentRun.advance_after_column_generated!(autonomous_run_id, column.id)
      end
      return
    end

    if column.generated_body?
      ensure_column_image!(column)
      return
    end

    return if GenerateColumnBodyJob.cancelled?(column_id)

    Rails.logger.info("[GenerateColumnBodyJob] start column_id=#{column_id} title=#{column.title.inspect}")

    GenerateColumnBodyJob.clear_cancellation!(column_id)
    runtime_mutex.synchronize { runtime_threads[column_id] = Thread.current }

    begin
      column.update!(generation_status: "generating")
      broadcast_generation_status(column)

      result = ColumnBodyGenerator.generate!(column)

      if result == :managed
        column.reload
        column.update!(generation_status: "completed") unless GenerateColumnBodyJob.cancelled?(column_id)
      elsif result.present? && !GptGenerationLocale.failed_output?(result)
        column.update!(body: result, status: "completed", generation_status: "completed")
      else
        raise "本文の生成に失敗しました（内容が空、またはエラーメッセージが含まれています）"
      end

      column.reload
      broadcast_generation_status(column)
      ensure_column_image!(column)
      broadcast_generation_status(column.reload)
      Rails.logger.info("[GenerateColumnBodyJob] completed column_id=#{column_id}")

      if autonomous_run_id.present?
        AutonomousContentRun.advance_after_column_generated!(autonomous_run_id, column.id)
      end

      run_quality_evaluation!(column.id)

    rescue StopRequested
      column.reload
      column.update_columns(generation_status: "cancelled")
      broadcast_generation_status(column)
      Rails.logger.info("⏹️ Generation stopped for column #{column_id}")

    rescue => e
      if ColumnBodyGenerator.cancelled_error?(e)
        column.update_columns(generation_status: "cancelled")
        broadcast_generation_status(column)
        Rails.logger.info("⏹️ Generation cancelled for column #{column_id}: #{e.message}")
      else
        error_info = "❌ 失敗: #{e.class} - #{e.message}\n場所: #{e.backtrace.first}"
        column.update_columns(status: "error", body: error_info, generation_status: "failed")
        broadcast_generation_status(column)
        Rails.logger.error("[GenerateColumnBodyJob] failed column_id=#{column_id} #{error_info}")

        if autonomous_run_id.present?
          run = AutonomousContentRun.find_by(id: autonomous_run_id)
          run&.mark_failed!(error_info)
        end

        raise e
      end

    ensure
      runtime_mutex.synchronize do
        runtime_threads.delete(column_id)
        runtime_cancelled_ids.delete(column_id)
      end
    end
  end

  def self.cancelled?(column_id)
    runtime_mutex.synchronize { runtime_cancelled_ids.include?(column_id) }
  end

  def self.clear_cancellation!(column_id)
    runtime_mutex.synchronize { runtime_cancelled_ids.delete(column_id) }
  end

  def self.request_stop!(column_id)
    runtime_mutex.synchronize { runtime_cancelled_ids.add(column_id) }

    thread = runtime_mutex.synchronize { runtime_threads[column_id] }
    return true unless thread&.alive?

    thread.raise(StopRequested)
    true
  end

  private

  def self.runtime_threads
    GenerationRuntime.running_threads
  end

  def self.runtime_cancelled_ids
    GenerationRuntime.cancelled_ids
  end

  def self.runtime_mutex
    GenerationRuntime.mutex
  end

  def runtime_threads
    self.class.runtime_threads
  end

  def runtime_cancelled_ids
    self.class.runtime_cancelled_ids
  end

  def runtime_mutex
    self.class.runtime_mutex
  end

  def broadcast_generation_status(column)
    GenerationChannelBroadcaster.broadcast(column)
  end

  def quality_score_present?(column)
    column.quality_score.present? && column.quality_score.to_f.positive?
  end

  def ensure_column_image!(column)
    column.reload
    return if FluxImageGeneratorService.already_generated?(column)

    Rails.logger.info("[GenerateColumnBodyJob] image start column_id=#{column.id}")
    FluxImageGeneratorService.generate!(column)
  rescue => e
    Rails.logger.error("[GenerateColumnBodyJob] image column_id=#{column.id} #{e.class}: #{e.message}")
    column.reload
    column.assign_stock_image_if_missing!
  end

  def run_quality_evaluation!(column_id)
    EvaluateColumnQualityJob.perform_now(column_id)
  rescue => e
    Rails.logger.error("❌ Evaluation error for column #{column_id}: #{e.message}")
  end
end
