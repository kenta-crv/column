class GenerateColumnBodyJob < ApplicationJob
  queue_as :article_generation

  # OpenAI APIのタイムアウトやネットワークエラー時に3回まで自動リトライ
  retry_on Net::ReadTimeout, wait: :exponentially_longer, attempts: 3

  def perform(column_id)
    column = Column.find_by(id: column_id)
    return unless column
    
    # 二重実行防止
    return if column.status == "completed" && column.body.present?

    # Set generation status to 'generating'
    column.update!(generation_status: 'generating')
    broadcast_generation_status(column)

    begin
      if column.article_type == "pillar"
        # 親記事(Pillar)の場合
        GptPillarGenerator.generate_full_from_existing_column!(column)
      else
        # 子記事(Child)の場合
        body = GptArticleGenerator.generate_body(column)
        
        if body.present? && !body.include?("生成失敗")
          # 💡 【修正】statusとgeneration_statusの更新を確実に保存
          column.update!(body: body, status: "completed", generation_status: 'completed')
        else
          raise "本文の生成に失敗しました（内容が空、またはエラーメッセージが含まれています）"
        end
      end
      
      broadcast_generation_status(column)
      
      # 💡 【修正】評価を非同期で実行（ActionCable経由で結果を通知）
      # Sidekiqを使わず、別スレッドで実行してブロッキングを回避
      Thread.new do
        begin
          EvaluateColumnQualityJob.perform_now(column.id)
        rescue => e
          Rails.logger.error("❌ Evaluation thread error: #{e.message}")
        end
      end
    rescue => e
      # 【証拠2】どこで落ちたかをDBに刻む（ログが消えてもDBで確認可能）
      error_info = "❌ 失敗: #{e.class} - #{e.message}\n場所: #{e.backtrace.first}"
      column.update_columns(status: "error", body: error_info, generation_status: 'failed')
      Rails.logger.error error_info
      broadcast_generation_status(column)
      raise e 
    end
  end

  private

  def broadcast_generation_status(column)
    # 💡 【修正】ActionCableのチャンネル名を 'GenerationChannel' に統一（文字列かクラス表記か）
    ActionCable.server.broadcast(
      'GenerationChannel',
      {
        column_id: column.id,
        status: column.generation_status,
        title: column.title
      }
    )
  end
end