class GenerateColumnBodyJob < ApplicationJob
  queue_as :article_generation

  # OpenAI APIのタイムアウトやネットワークエラー時に3回まで自動リトライ
  retry_on Net::ReadTimeout, wait: :exponentially_longer, attempts: 3

  def perform(column_id, autonomous_run_id: nil)
    AutonomousContentRun.recover_stale_runs! if autonomous_run_id.present?

    column = Column.find_by(id: column_id)
    return unless column

    # 親記事: 本文が既にあれば再生成せず、自律runの後続処理だけ進める
    if column.article_type == "pillar" && column.body.present?
      if autonomous_run_id.present?
        AutonomousContentRun.advance_after_column_generated!(autonomous_run_id, column.id)
      end
      return
    end

    # 二重実行防止
    return if column.status == "completed" && column.body.present?
    return if column.generation_status == "generating"

    column.update!(generation_status: "generating")
    broadcast_generation_status(column)

    begin
      if column.article_type == "pillar"
        GptPillarGenerator.generate_full_from_existing_column!(column)
        column.update!(generation_status: "completed") if column.body.present?
      else
        body = GptArticleGenerator.generate_body(column)

        if body.present? && !body.include?("生成失敗")
          column.update!(body: body, status: "completed", generation_status: "completed")
        else
          raise "本文の生成に失敗しました（内容が空、またはエラーメッセージが含まれています）"
        end
      end

      broadcast_generation_status(column)

      if autonomous_run_id.present?
        AutonomousContentRun.advance_after_column_generated!(autonomous_run_id, column.id)
      end

      EvaluateColumnQualityJob.perform_later(column.id)
    rescue => e
      error_info = "#{e.class}: #{e.message}"
      column.update_columns(status: "error", generation_status: "failed")
      Rails.logger.error("#{error_info}\n#{e.backtrace.first(5).join("\n")}")
      broadcast_generation_status(column)

      if autonomous_run_id.present?
        run = AutonomousContentRun.find_by(id: autonomous_run_id)
        run&.mark_failed!(error_info)
      end

      raise e
    ensure
      column&.reload
      if column && column.generation_status == "generating"
        if column.body.present?
          column.update_columns(generation_status: "completed")
        else
          column.update_columns(generation_status: "failed", status: "error")
          if autonomous_run_id.present?
            run = AutonomousContentRun.find_by(id: autonomous_run_id)
            run&.mark_failed!("記事の生成が異常終了しました。") if run && %w[queued generating_pillar generating_children].include?(run.status)
          end
        end
        broadcast_generation_status(column)
      end
    end
  end

  private

  def broadcast_generation_status(column)
    ActionCable.server.broadcast(
      GenerationChannel::STREAM_NAME,
      {
        column_id: column.id,
        status: column.generation_status,
        title: column.title
      }
    )
  end
end
