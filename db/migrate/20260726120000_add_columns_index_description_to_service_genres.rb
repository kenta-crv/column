class AddColumnsIndexDescriptionToServiceGenres < ActiveRecord::Migration[6.1]
  def up
    add_column :service_genres, :columns_index_description, :text

    say_with_time "backfill columns_index_description" do
      ServiceGenre.reset_column_information
      ServiceGenre.find_each do |genre|
        next if genre.columns_index_description.to_s.strip.present?

        genre.update_columns(columns_index_description: genre.default_columns_index_description)
      end
    end
  end

  def down
    remove_column :service_genres, :columns_index_description
  end
end
