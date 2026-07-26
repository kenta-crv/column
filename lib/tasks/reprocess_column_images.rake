namespace :columns do
  desc "既存の記事画像を WebP に一括変換（縮小込み）。DRY_RUN=1 で確認のみ。LIMIT=N で件数制限。"
  task reprocess_images_webp: :environment do
    dry_run = ENV["DRY_RUN"].to_s == "1"
    limit = ENV["LIMIT"].to_i

    scope = Column.where.not(file: [nil, ""])
    total = scope.count
    scope = scope.limit(limit) if limit.positive?

    puts "Target: #{scope.count}/#{total} columns (dry_run=#{dry_run})"

    ok = 0
    skip = 0
    fail = 0

    scope.find_each do |column|
      path = begin
        column.file.path
      rescue StandardError
        nil
      end

      unless path.present? && File.exist?(path)
        puts "SKIP missing id=#{column.id} file=#{column.read_attribute(:file)}"
        skip += 1
        next
      end

      ext = File.extname(path).downcase
      if ext == ".webp"
        puts "SKIP already webp id=#{column.id}"
        skip += 1
        next
      end

      if dry_run
        size_kb = (File.size(path) / 1024.0).round(1)
        puts "WOULD convert id=#{column.id} #{File.basename(path)} (#{size_kb}KB)"
        ok += 1
        next
      end

      begin
        old_path = path
        old_name = File.basename(path)
        content_type = case ext
                       when ".png" then "image/png"
                       when ".gif" then "image/gif"
                       else "image/jpeg"
                       end

        Dir.mktmpdir("column-webp-#{column.id}-") do |tmpdir|
          tmp = File.join(tmpdir, old_name)
          FileUtils.cp(old_path, tmp)

          File.open(tmp, "rb") do |io|
            io.define_singleton_method(:original_filename) { old_name }
            io.define_singleton_method(:content_type) { content_type }
            column.file = io
            column.save!
          end
        end

        new_path = column.file.path
        if old_path != new_path && File.exist?(old_path)
          FileUtils.rm_f(old_path)
        end

        new_kb = File.exist?(new_path.to_s) ? (File.size(new_path) / 1024.0).round(1) : "?"
        puts "OK id=#{column.id} -> #{File.basename(new_path.to_s)} (#{new_kb}KB)"
        ok += 1
      rescue StandardError => e
        puts "FAIL id=#{column.id}: #{e.class}: #{e.message}"
        fail += 1
      end
    end

    puts "Done ok=#{ok} skip=#{skip} fail=#{fail}"
  end
end
