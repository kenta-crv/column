class CreateServiceGenres < ActiveRecord::Migration[6.1]
  def change
    create_table :service_genres do |t|
      t.references :client, foreign_key: true, null: true
      t.string :key, null: false
      t.string :ja, null: false
      t.string :service_name
      t.text :strong_points
      t.json :hosts, default: []
      t.json :keywords, default: []
      t.json :images, default: []
      t.json :sub_categories, default: {}

      t.timestamps
    end

    add_index :service_genres, [:client_id, :key], unique: true
  end
end
