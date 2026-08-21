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

  desc "Rewrite UUID/blank/article-id codes to SEO slugs. USE_GPT=1 (default), DRY_RUN=1, LIMIT=n"
  task rewrite_placeholder_codes: :environment do
    use_gpt = ENV["USE_GPT"] != "0"
    dry_run = ENV["DRY_RUN"] == "1"
    limit = ENV["LIMIT"].presence&.to_i

    targets = []
    Column.find_each do |column|
      next unless column.placeholder_code?

      targets << column
      break if limit && targets.size >= limit
    end

    puts "placeholder=#{targets.size} use_gpt=#{use_gpt} dry_run=#{dry_run}"
    updated = 0
    skipped = 0

    targets.each_with_index do |column, index|
      new_code = column.propose_seo_code(use_gpt: use_gpt)
      if new_code.blank?
        skipped += 1
        puts "[skip] ##{column.id} code=#{column.code.inspect} title=#{column.title.to_s.truncate(60)}"
        next
      end

      if dry_run
        puts "[dry] ##{column.id} #{column.code.inspect} -> #{new_code}"
      else
        old = column.code
        column.persist_seo_code!(new_code)
        puts "[ok] ##{column.id} #{old.inspect} -> #{column.code}"
        updated += 1
      end

      sleep 0.25 if use_gpt && !dry_run && index < targets.size - 1
    end

    puts "done. updated=#{updated} skipped=#{skipped}"
  end
end
