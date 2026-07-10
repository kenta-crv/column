class GenerateColumnBodyJob < ApplicationJob
  queue_as :article_generation

  retry_on Net::ReadTimeout, wait: :exponentially_longer, attempts: 3

  class StopRequested < StandardError; end

  def perform(column_id)
    column = Column.find_by(id: column_id)
    return unless column
    return if column.generated_body?

    return if GenerateColumnBodyJob.cancelled?(column_id)

    Rails.logger.info("[GenerateColumnBodyJob] start column_id=#{column_id} title=#{column.title.inspect}")

    GenerateColumnBodyJob.clear_cancellation!(column_id)
    runtime_mutex.synchronize { runtime_threads[column_id] = Thread.current }

    begin
      column.update!(generation_status: "generating")
      broadcast_generation_status(column)

      if column.article_type == "pillar"
        GptPillarGenerator.generate_full_from_existing_column!(column)
        column.reload
        column.update!(generation_status: "completed") unless GenerateColumnBodyJob.cancelled?(column_id)
      else
        body = GptArticleGenerator.generate_body(column)
        if body.present? && !body.include?("生成失敗")
          column.update!(body: body, status: "completed", generation_status: "completed")
        else
          raise "本文の生成に失敗しました（内容が空、またはエラーメッセージが含まれています）"
        end
      end

      broadcast_generation_status(column)
      Rails.logger.info("[GenerateColumnBodyJob] completed column_id=#{column_id}")

      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          EvaluateColumnQualityJob.perform_now(column.id)
        end
      rescue => e
        Rails.logger.error("❌ Evaluation thread error: #{e.message}")
      end

    rescue StopRequested
      column.reload
      column.update_columns(generation_status: "cancelled")
      broadcast_generation_status(column)
      Rails.logger.info("⏹️ Generation stopped for column #{column_id}")

    rescue GptArticleGenerator::GenerationCancelledError,
           GptPillarGenerator::GenerationCancelledError => e
      column.update_columns(generation_status: "cancelled")
      broadcast_generation_status(column)
      Rails.logger.info("⏹️ Generation cancelled for column #{column_id}: #{e.message}")

    rescue => e
      error_info = "❌ 失敗: #{e.class} - #{e.message}\n場所: #{e.backtrace.first}"
      column.update_columns(status: "error", body: error_info, generation_status: "failed")
      broadcast_generation_status(column)
      Rails.logger.error("[GenerateColumnBodyJob] failed column_id=#{column_id} #{error_info}")
      raise e

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
end
