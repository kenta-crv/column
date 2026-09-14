# frozen_string_literal: true

# 手書き本文を消し、ひらがな言語のまま「本文未生成」状態へ戻す。
# その後、通常の本文生成ジョブを起動する。

CODES = %w[
  juminhyo-toroku-kantan-nihongo
  juminhyo-henko-kantan-nihongo
  ginko-kozashinsei-osusume-kantan-nihongo
  rosai-kantan-nihongo
  miharai-chingin-kantan-nihongo
].freeze

raise "hiragana not enabled" unless Column::LANGUAGES.include?("hiragana")

ids = []
CODES.each do |code|
  column = Column.find_by!(code: code)
  if %w[generating queued].include?(column.generation_status)
    GenerateColumnBodyJob.request_stop!(column.id) if defined?(GenerateColumnBodyJob)
  end

  column.update!(
    body: nil,
    description: nil,
    published_at: nil,
    status: "draft",
    generation_status: "idle",
    language: "hiragana",
    quality_score: 0.0,
    evaluation_metrics: {}
  )
  ids << column.id
  puts "RESET | #{column.id} | #{column.language} | body?=#{column.generated_body?} | #{column.code}"
end

pending = Column.where(id: ids).merge(Column.without_generated_body).pluck(:id)
puts "pending=#{pending.size}"

Column.where(id: pending).update_all(
  status: "approved",
  generation_status: "queued",
  updated_at: Time.current
)

Thread.new do
  Rails.application.executor.wrap do
    ActiveRecord::Base.connection_pool.with_connection do
      pending.each do |column_id|
        begin
          column = Column.find_by(id: column_id)
          next if column.nil? || column.generated_body?

          GenerateColumnBodyJob.clear_cancellation!(column_id)
          GenerateColumnBodyJob.perform_now(column_id)
          reloaded = Column.find(column_id)
          puts "GEN | #{column_id} | status=#{reloaded.generation_status} | body?=#{reloaded.generated_body?} | lang=#{reloaded.language}"
        rescue => e
          puts "ERR | #{column_id} | #{e.class}: #{e.message}"
          Rails.logger.error("[HiraganaRegen] column_id=#{column_id} #{e.class}: #{e.message}")
        end
      end
    end
  end
end

puts "STARTED generation for #{pending.size} columns"
# give the thread a moment to attach logs for first job start
sleep 2
puts "DONE kickoff"
