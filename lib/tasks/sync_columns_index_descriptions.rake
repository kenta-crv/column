namespace :genres do
  desc "FALLBACK_GENRES の columns_index_description を service_genres（client_id nil）へ反映。DRY_RUN=1 で確認のみ。"
  task sync_columns_index_descriptions: :environment do
    dry_run = ENV["DRY_RUN"].to_s == "1"
    updated = 0
    created = 0
    skipped = 0

    GenreRegistry::FALLBACK_GENRES.each do |key, data|
      desc = data[:columns_index_description].to_s.strip
      if desc.blank?
        puts "SKIP #{key} (no description in FALLBACK)"
        skipped += 1
        next
      end

      record = ServiceGenre.find_or_initialize_by(client_id: nil, key: key.to_s)
      is_new = record.new_record?

      if is_new
        record.ja = data[:ja].to_s
        record.service_name = data[:service_name].to_s
        record.strong_points = data[:strong_points]
        record.hosts = Array(data[:host])
        record.keywords = Array(data[:keywords])
        record.images = Array(data[:images])
        record.sub_categories = ServiceGenre.stringify_nested(data[:sub_categories] || {})
      end

      if record.columns_index_description.to_s.strip == desc && !is_new
        puts "OK #{key} (unchanged)"
        skipped += 1
        next
      end

      puts "#{is_new ? 'CREATE' : 'UPDATE'} #{key} -> #{desc.truncate(70)}"
      next if dry_run

      record.columns_index_description = desc
      record.admin_override = true
      record.save!
      is_new ? created += 1 : updated += 1
    end

    GenreRegistry.reset!
    puts "Done created=#{created} updated=#{updated} skipped=#{skipped} dry_run=#{dry_run}"
  end
end
