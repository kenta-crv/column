class AddEnToServiceGenres < ActiveRecord::Migration[6.1]
  def change
    add_column :service_genres, :en, :string
  end
end
