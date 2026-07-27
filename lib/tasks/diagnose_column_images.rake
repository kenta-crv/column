# frozen_string_literal: true

namespace :columns do
  desc "画像参照の診断。CODE=slug で1件詳細。RAILS_ENV=production 必須。"
  task diagnose_images: :environment do
    root = Rails.root.join("public", "uploads", "column", "file")
    dir_count = root.directory? ? root.children.count { |p| p.directory? } : 0
    with_file = Column.where.not(file: [nil, ""]).count
    blank_file = Column.where(file: [nil, ""]).count
    published = Column.published.count

    puts "Rails.root=#{Rails.root}"
    puts "RAILS_ENV=#{Rails.env}"
    puts "upload_dirs=#{dir_count}"
    puts "columns_with_file=#{with_file} blank_file=#{blank_file} published=#{published}"

    if (code = ENV["CODE"].to_s.strip).present?
      column = Column.find_by(code: code)
      if column.nil?
        puts "COLUMN_NOT_FOUND code=#{code}"
      else
        dir = root.join(column.id.to_s)
        files = dir.directory? ? dir.children.select(&:file?).map(&:basename).map(&:to_s) : []
        path = begin
          column.file.path
        rescue StandardError
          nil
        end
        puts({
          id: column.id,
          code: column.code,
          db_file: column[:file],
          carrierwave_present: column.file.present?,
          image_file_stored: column.image_file_stored?,
          path: path,
          path_exists: path.present? && File.exist?(path.to_s),
          dir_exists: dir.directory?,
          dir_files: files
        }.inspect)
      end
    end

    missing_disk = 0
    Column.where.not(file: [nil, ""]).limit(200).find_each do |column|
      missing_disk += 1 unless column.image_file_stored?
    end
    puts "sample_missing_disk_among_with_file(<=200)=#{missing_disk}"
  end
end
