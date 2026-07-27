# frozen_string_literal: true

namespace :genres do
  desc "ColumnServiceCta のデフォルトを service_genres.column_cta へ反映。FORCE=1 で上書き。DRY_RUN=1 で確認のみ。"
  task sync_column_ctas: :environment do
    dry_run = ENV["DRY_RUN"].to_s == "1"
    force = ENV["FORCE"].to_s == "1"
    updated = 0
    skipped = 0
    missing = 0

    ColumnServiceCta::CTAS.each_key do |key|
      default = ColumnServiceCta.default_payload_for(key)
      next if default.blank?

      payload = ColumnServiceCta.stringify_payload(default)
      records = ServiceGenre.where(key: GenreRegistry.equivalent_keys(key), client_id: nil)

      if records.none?
        missing += 1
        puts "[miss] #{key} — service_genres にシステム共通レコードがありません"
        next
      end

      records.find_each do |record|
        current = record.column_cta
        if !force && current.present? && current != {}
          skipped += 1
          puts "[skip] #{record.key}##{record.id}（既存あり。上書きは FORCE=1）"
          next
        end

        if dry_run
          puts "[dry]  #{record.key}##{record.id}"
        else
          record.update!(column_cta: payload)
          puts "[ok]   #{record.key}##{record.id}"
        end
        updated += 1
      end
    end

    puts "done updated=#{updated} skipped=#{skipped} missing_keys=#{missing} dry_run=#{dry_run} force=#{force}"
  end
end
