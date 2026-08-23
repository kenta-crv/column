# frozen_string_literal: true

# J Work の cargo を「外国人」メイン＋中分類3つに合わせる。
# URL key（cargo）と既存記事の sub_genre（delivery_partner / driver_recruitment）は維持する。
class RepositionJworkCargoAsForeigners < ActiveRecord::Migration[6.1]
  def up
    return unless table_exists?(:service_genres)

    data = GenreRegistry::FALLBACK_GENRES[:cargo]
    return if data.blank?

    cta = ColumnServiceCta.default_payload_for("cargo")

    say_with_time "sync cargo ServiceGenre to foreigners taxonomy" do
      ServiceGenre.where(key: "cargo").find_each do |genre|
        genre.ja = data[:ja]
        genre.en = data[:en] if genre.has_attribute?(:en)
        genre.service_name = data[:service_name]
        genre.strong_points = data[:strong_points]
        genre.keywords = Array(data[:keywords])
        genre.images = Array(data[:images]) if Array(genre.images).blank?
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

    GenreRegistry.reset! if defined?(GenreRegistry)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
