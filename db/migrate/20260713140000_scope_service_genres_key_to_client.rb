class ScopeServiceGenresKeyToClient < ActiveRecord::Migration[6.1]
  def up
    if index_exists?(:service_genres, :key)
      remove_index :service_genres, :key
    end

    unless index_exists?(:service_genres, [:client_id, :key])
      add_index :service_genres, [:client_id, :key], unique: true
    end
  end

  def down
    if index_exists?(:service_genres, [:client_id, :key])
      remove_index :service_genres, column: [:client_id, :key]
    end

    unless index_exists?(:service_genres, :key)
      add_index :service_genres, :key, unique: true
    end
  end
end
