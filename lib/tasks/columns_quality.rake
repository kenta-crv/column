namespace :columns do
  desc "Re-evaluate AI quality scores for generated articles (optional LIMIT, default 20)"
  task :reevaluate_quality, [:limit] => :environment do |_task, args|
    limit = (args[:limit].presence || 20).to_i
    scope = Column.with_generated_body.order(updated_at: :desc).limit(limit)

    puts "Re-evaluating #{scope.count} column(s)..."
    scope.find_each do |column|
      EvaluateColumnQualityJob.perform_now(column.id)
      column.reload
      puts "  ##{column.id} #{column.title.to_s.truncate(40)} => #{column.quality_score}"
    end
    puts "done."
  end
end
