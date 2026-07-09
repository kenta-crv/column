class AddUniqueIndexToServiceGenresKey < ActiveRecord::Migration[6.1]
  def up
    remove_index :service_genres, column: [:client_id, :key]

    duplicates = ServiceGenre.group(:key).having("COUNT(*) > 1").pluck(:key)
    if duplicates.any?
      raise ActiveRecord::IrreversibleMigration,
            "service_genres.key の重複があります: #{duplicates.join(', ')}。マージしてから再実行してください。"
    end

    add_index :service_genres, :key, unique: true
  end

  def down
    remove_index :service_genres, :key
    add_index :service_genres, [:client_id, :key], unique: true
  end
end
