# frozen_string_literal: true

# 本文保存後にアイキャッチを付ける。失敗しても本文完了は維持する。
class GenerateColumnImageJob < ApplicationJob
  queue_as :article_generation

  def perform(column_id)
    column = Column.find_by(id: column_id)
    return unless column
    return unless column.generated_body?
    return if FluxImageGeneratorService.already_generated?(column)

    Rails.logger.info("[GenerateColumnImageJob] start column_id=#{column_id}")
    FluxImageGeneratorService.generate!(column)
    Rails.logger.info("[GenerateColumnImageJob] completed column_id=#{column_id}")
  rescue => e
    Rails.logger.error("[GenerateColumnImageJob] column_id=#{column_id} #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.first(8).join("\n"))
    column&.reload
    column&.assign_stock_image_if_missing!
  end
end
