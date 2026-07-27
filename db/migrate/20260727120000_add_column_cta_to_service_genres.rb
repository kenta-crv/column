# frozen_string_literal: true

class AddColumnCtaToServiceGenres < ActiveRecord::Migration[6.1]
  def up
    add_column :service_genres, :column_cta, :json, default: {}

    say_with_time "backfill column_cta from ColumnServiceCta defaults" do
      ServiceGenre.reset_column_information
      ServiceGenre.find_each do |genre|
        next if genre.column_cta.present? && genre.column_cta != {}

        default = ColumnServiceCta.default_payload_for(genre.key)
        next if default.blank?

        genre.update_columns(column_cta: ColumnServiceCta.stringify_payload(default))
      end
    end
  end

  def down
    remove_column :service_genres, :column_cta
  end
end
