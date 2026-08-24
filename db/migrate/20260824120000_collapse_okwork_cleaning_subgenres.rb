# frozen_string_literal: true

# OK清掃の中分類を5つに再編し、特殊清掃（emergency_cleaning）を cleaning へ寄せる。
class CollapseOkworkCleaningSubgenres < ActiveRecord::Migration[6.1]
  OLD_GENRE = "emergency_cleaning"
  NEW_GENRE = "cleaning"

  SUB_MAP = {
    "office" => "daily_standard",
    "school" => "daily_standard",
    "nursery_school" => "daily_standard",
    "public_facility" => "daily_standard",
    "nursing_home" => "daily_standard",
    "medical_facility" => "daily_standard",
    "factory" => "daily_standard",
    "restaurant" => "daily_standard",
    "daily_standard" => "daily_standard",
    "building" => "apartment",
    "apartment" => "apartment",
    "periodic" => "periodic",
    "turnover" => "turnover",
    "special" => "special"
  }.freeze

  def up
    rewrite_columns_genre_and_sub! if table_exists?(:columns)
    rewrite_runs_genre! if table_exists?(:autonomous_content_runs)
    rewrite_allowed_genres! if table_exists?(:clients) && column_exists?(:clients, :allowed_genres)
    unify_service_genres! if table_exists?(:service_genres)
    sync_cleaning_service_genre! if table_exists?(:service_genres)
    GenreRegistry.reset! if defined?(GenreRegistry)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def rewrite_columns_genre_and_sub!
    return unless column_exists?(:columns, :genre)

    if column_exists?(:columns, :sub_genre)
      SUB_MAP.each do |from, to|
        execute ActiveRecord::Base.sanitize_sql_array(
          ["UPDATE columns SET sub_genre = ? WHERE genre IN (?, ?) AND sub_genre = ?", to, NEW_GENRE, OLD_GENRE, from]
        )
      end
      execute ActiveRecord::Base.sanitize_sql_array(
        [
          "UPDATE columns SET sub_genre = ? WHERE genre = ? AND (sub_genre IS NULL OR sub_genre = '')",
          "special",
          OLD_GENRE
        ]
      )
    end

    execute ActiveRecord::Base.sanitize_sql_array(
      ["UPDATE columns SET genre = ? WHERE genre = ?", NEW_GENRE, OLD_GENRE]
    )
  end

  def rewrite_runs_genre!
    return unless column_exists?(:autonomous_content_runs, :genre)

    execute ActiveRecord::Base.sanitize_sql_array(
      ["UPDATE autonomous_content_runs SET genre = ? WHERE genre = ?", NEW_GENRE, OLD_GENRE]
    )
  end

  def rewrite_allowed_genres!
    Client.find_each do |client|
      list = Array(client.allowed_genres)
      next if list.blank?

      rewritten = list.map { |v| v.to_s == OLD_GENRE ? NEW_GENRE : v.to_s }.uniq
      next if rewritten == list.map(&:to_s)

      client.update_columns(allowed_genres: rewritten)
    end
  end

  def unify_service_genres!
    client_ids = ServiceGenre.where(key: [OLD_GENRE, NEW_GENRE]).distinct.pluck(:client_id)

    client_ids.each do |client_id|
      scope = ServiceGenre.where(client_id: client_id)
      old_row = scope.find_by(key: OLD_GENRE)
      new_row = scope.find_by(key: NEW_GENRE)

      if old_row && new_row
        old_row.destroy!
      elsif old_row && !new_row
        old_row.update!(key: NEW_GENRE)
      end
    end
  end

  def sync_cleaning_service_genre!
    data = GenreRegistry::FALLBACK_GENRES[:cleaning]
    return if data.blank?

    cta = ColumnServiceCta.default_payload_for("cleaning")

    ServiceGenre.where(key: NEW_GENRE).find_each do |genre|
      genre.ja = data[:ja]
      genre.en = data[:en] if genre.has_attribute?(:en)
      genre.service_name = data[:service_name]
      genre.keywords = Array(data[:keywords])
      if genre.has_attribute?(:columns_index_description)
        genre.columns_index_description = data[:columns_index_description]
      end
      genre.sub_categories = ServiceGenre.stringify_nested(data[:sub_categories] || {})
      if genre.has_attribute?(:column_cta) && cta.present?
        genre.column_cta = ColumnServiceCta.stringify_payload(cta)
      end
      genre.save!(validate: false)
    end
  end
end
