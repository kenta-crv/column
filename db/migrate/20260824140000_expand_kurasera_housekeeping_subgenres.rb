# frozen_string_literal: true

# クラセラ（housekeeping）中分類を家事代行・シッター・高齢者補助へ展開する。
class ExpandKuraseraHousekeepingSubgenres < ActiveRecord::Migration[6.1]
  def up
    rewrite_columns_sub! if table_exists?(:columns) && column_exists?(:columns, :sub_genre)
    sync_housekeeping_service_genre! if table_exists?(:service_genres)
    GenreRegistry.reset! if defined?(GenreRegistry)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def rewrite_columns_sub!
    execute ActiveRecord::Base.sanitize_sql_array(
      [
        "UPDATE columns SET sub_genre = ? WHERE genre IN (?, ?) AND sub_genre = ?",
        "kaji_daiko",
        "housekeeping",
        "家事代行",
        "basic_cleaning"
      ]
    )
  end

  def sync_housekeeping_service_genre!
    data = GenreRegistry::FALLBACK_GENRES[:housekeeping]
    return if data.blank?

    cta = ColumnServiceCta.default_payload_for("housekeeping")

    ServiceGenre.where(key: "housekeeping").find_each do |genre|
      genre.ja = data[:ja]
      genre.en = data[:en] if genre.has_attribute?(:en)
      genre.service_name = data[:service_name]
      genre.keywords = Array(data[:keywords])
      genre.strong_points = data[:strong_points] if genre.has_attribute?(:strong_points)
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
