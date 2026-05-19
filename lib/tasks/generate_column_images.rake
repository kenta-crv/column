namespace :columns do
  desc "Generate images for existing columns"

  task generate_images: :environment do
    columns = Column.where(file: [nil, ""])
                    .where.not(body: [nil, ""])

    puts "Target columns: #{columns.count}"

    columns.find_each do |column|
      begin
        FluxImageGeneratorService.generate!(column)

        puts "Generated Column ID: #{column.id}"
      rescue => e
        puts "Failed Column ID: #{column.id}"
        puts e.message
      end

      sleep 1
    end

    puts "Done"
  end
end