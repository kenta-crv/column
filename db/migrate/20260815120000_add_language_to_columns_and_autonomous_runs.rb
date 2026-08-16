class AddLanguageToColumnsAndAutonomousRuns < ActiveRecord::Migration[6.1]
  def change
    add_column :columns, :language, :string, null: false, default: "ja"
    add_index :columns, :language

    add_column :autonomous_content_runs, :language, :string, null: false, default: "ja"
  end
end
