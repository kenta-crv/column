# frozen_string_literal: true

# cargo 中分類に生活実務・特定技能・支援団体・労働相談を追加する。
class AddJworkCargoLifeAndSupportSubgenres < ActiveRecord::Migration[6.1]
  def up
    return unless table_exists?(:service_genres)

    data = GenreRegistry::FALLBACK_GENRES[:cargo]
    return if data.blank?

    cta = ColumnServiceCta.default_payload_for("cargo")

    say_with_time "add life_guide / specified_skills / support_orgs / labor_help to cargo" do
      ServiceGenre.where(key: "cargo").find_each do |genre|
        genre.columns_index_description = data[:columns_index_description] if genre.has_attribute?(:columns_index_description)
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
