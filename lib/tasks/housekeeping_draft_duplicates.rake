# frozen_string_literal: true

namespace :housekeeping do
  desc "重複テーマの余剰記事を下書き化。7月以降を優先して代表を残す。EXECUTE=1 で実行。SLUGS_FILE=path 指定時はその code のみ下書き化"
  task draft_duplicates: :environment do
    dry_run = ENV["EXECUTE"] != "1"
    cutoff = Time.zone.parse(ENV.fetch("CUTOFF", "2026-07-01"))
    genre_keys = %w[housekeeping 家事代行]
    slug_file = ENV["SLUGS_FILE"].presence

    if slug_file
      unless File.exist?(slug_file)
        abort "SLUGS_FILE not found: #{slug_file}"
      end

      draft_slugs = File.readlines(slug_file).map(&:strip).reject(&:blank?)
      targets = Column.where(code: draft_slugs).where.not(published_at: nil)
      puts "Mode: SLUGS_FILE (#{draft_slugs.size} slugs), published matches=#{targets.count}, dry_run=#{dry_run}"

      unpublished = 0
      targets.find_each do |column|
        if dry_run
          puts "  [DRY] unpublish ##{column.id} #{column.code} #{column.title.to_s.truncate(50)}"
        else
          column.unpublish!
          column.update_columns(status: "draft") if column.has_attribute?(:status)
          unpublished += 1
          puts "  unpublished ##{column.id} #{column.code}"
        end
      end

      missing = draft_slugs - Column.where(code: draft_slugs).pluck(:code)
      puts "missing codes: #{missing.size}" if missing.any?
      puts(dry_run ? "DRY_RUN complete. EXECUTE=1 で実行してください。" : "Done. unpublished=#{unpublished}")
      next
    end

    columns = Column.where(genre: genre_keys).to_a
    puts "Mode: theme-dedupe, housekeeping columns=#{columns.size}, cutoff=#{cutoff}, dry_run=#{dry_run}"

    theme_rules = [
      ["ハウスクリーニング", [/ハウスクリーニング/, /ハウスキーパー/]],
      ["ロボット掃除機", [/ロボット掃除機/]],
      ["水回り", [/水回り/]],
      ["汚部屋", [/汚部屋/]],
      ["選び方", [/選び方/]],
      ["料金", [/料金/, /費用/, /相場/]],
      ["トラブルNG", [/トラブル/, /NG/, /危険/, /危ない/, /失敗/, /クレーム/, /盗難/]],
      ["一人暮らし共働き", [/一人暮らし/, /共働き/, /独身/]],
      ["料理作り置き", [/料理/, /作り置き/]],
      ["利用の流れ", [/利用の流れ/, /申し込み/, /依頼方法/, /初めて/]],
      ["頼める範囲", [/頼める/, /頼めない/, /サービス一覧/, /特別なサービス/, /業務内容/]]
    ]

    grouped = Hash.new { |h, k| h[k] = [] }
    ungrouped = []

    columns.each do |column|
      title = column.title.to_s
      theme = theme_rules.find { |_name, pats| pats.any? { |re| title.match?(re) } }&.first
      if theme
        grouped[theme] << column
      else
        ungrouped << column
      end
    end

    draft_ids = []

    grouped.each do |theme, items|
      ranked = items.sort_by do |c|
        ref = c.updated_at || c.published_at || Time.zone.at(0)
        july = ref >= cutoff ? 1 : 0
        [-july, -ref.to_i]
      end
      keeper = ranked.first
      puts "KEEP [#{theme}] ##{keeper.id} #{keeper.code} #{keeper.title.to_s.truncate(40)} (updated=#{keeper.updated_at})"
      ranked.drop(1).each do |column|
        next if column.published_at.blank?

        draft_ids << column.id
      end
    end

    puts "Ungrouped kept as-is: #{ungrouped.size}"
    puts "Draft candidates: #{draft_ids.size}"

    unpublished = 0
    Column.where(id: draft_ids).find_each do |column|
      if dry_run
        puts "  [DRY] unpublish ##{column.id} #{column.code} #{column.title.to_s.truncate(50)}"
      else
        column.unpublish!
        column.update_columns(status: "draft") if column.has_attribute?(:status)
        unpublished += 1
      end
    end

    puts(dry_run ? "DRY_RUN complete. EXECUTE=1 で実行してください。" : "Done. unpublished=#{unpublished}")
  end
end
