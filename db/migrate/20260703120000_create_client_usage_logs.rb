class CreateClientUsageLogs < ActiveRecord::Migration[6.1]
  def change
    create_table :client_usage_logs do |t|
      t.references :client, null: false, foreign_key: true
      t.string :period, null: false
      t.integer :title_suggestion_count, null: false, default: 0
      t.integer :image_generation_count, null: false, default: 0

      t.timestamps
    end

    add_index :client_usage_logs, [:client_id, :period], unique: true
  end
end
