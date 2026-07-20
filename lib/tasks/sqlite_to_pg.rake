# frozen_string_literal: true

# 使い方（本番サーバー）:
#   sudo -u postgres psql -c "ALTER USER drafity WITH SUPERUSER;"
#   RAILS_ENV=production DISABLE_SPRING=1 bundle exec rake db:sqlite_to_pg
#   sudo -u postgres psql -c "ALTER USER drafity WITH NOSUPERUSER;"
#
# SQLite のパスは ENV['SQLITE_PATH'] で上書き可（既定: db/development.sqlite3）

namespace :db do
  desc "Copy data from SQLite into current DB (PostgreSQL), preserving IDs"
  task sqlite_to_pg: :environment do
    sqlite_path = ENV.fetch("SQLITE_PATH", Rails.root.join("db/development.sqlite3").to_s)
    raise "SQLite file not found: #{sqlite_path}" unless File.exist?(sqlite_path)

    sqlite_cfg = {
      adapter: "sqlite3",
      database: sqlite_path,
      pool: 5,
      timeout: 5000
    }

    klass = Class.new(ActiveRecord::Base) do
      self.abstract_class = true
    end
    klass.establish_connection(sqlite_cfg)

    skip = %w[schema_migrations ar_internal_metadata]
    tables = ActiveRecord::Base.connection.tables.sort - skip

    begin
      ActiveRecord::Base.connection.execute("SET session_replication_role = replica")
    rescue ActiveRecord::StatementInvalid => e
      raise "Need SUPERUSER (or REPLICATION) for import: #{e.message}"
    end

    tables.each do |table|
      next unless klass.connection.table_exists?(table)

      cols = klass.connection.columns(table).map(&:name) &
             ActiveRecord::Base.connection.columns(table).map(&:name)
      next if cols.empty?

      sql_cols = cols.map { |c| %("#{c}") }.join(", ")
      rows = klass.connection.exec_query("SELECT #{sql_cols} FROM #{table}")
      next if rows.rows.empty?

      quoted_cols = cols.map { |c| ActiveRecord::Base.connection.quote_column_name(c) }.join(", ")
      inserted = 0
      rows.rows.each do |row|
        values = row.map { |v| ActiveRecord::Base.connection.quote(v) }.join(", ")
        ActiveRecord::Base.connection.execute(
          "INSERT INTO #{table} (#{quoted_cols}) VALUES (#{values})"
        )
        inserted += 1
      end
      ActiveRecord::Base.connection.reset_pk_sequence!(table) if cols.include?("id")
      puts "#{table}: #{inserted}"
    end

    ActiveRecord::Base.connection.execute("SET session_replication_role = DEFAULT")
    puts "DONE"

    %w[admins clients columns subscriptions].each do |t|
      next unless klass.connection.table_exists?(t) && ActiveRecord::Base.connection.table_exists?(t)

      s = klass.connection.select_value("SELECT COUNT(*) FROM #{t}")
      p = ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{t}")
      puts "compare #{t}: sqlite=#{s} pg=#{p}"
    end
  end
end
