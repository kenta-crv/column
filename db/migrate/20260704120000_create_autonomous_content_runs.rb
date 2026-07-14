class CreateAutonomousContentRuns < ActiveRecord::Migration[6.1]
  def change
    add_column :clients, :autonomous_settings, :json

    create_table :autonomous_content_runs do |t|
      t.references :client, null: false, foreign_key: true
      t.references :pillar_column, foreign_key: { to_table: :columns }
      t.string :title, null: false
      t.string :genre, null: false
      t.integer :cluster_limit, null: false, default: 15
      t.string :status, null: false, default: "queued"
      t.string :pause_for_approval_at
      t.json :notify_on
      t.json :next_pillar_titles
      t.text :error_message

      t.timestamps
    end

    add_index :autonomous_content_runs, :status
    add_index :autonomous_content_runs, [:client_id, :status]
  end
end
