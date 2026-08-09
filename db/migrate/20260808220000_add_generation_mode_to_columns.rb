class AddGenerationModeToColumns < ActiveRecord::Migration[6.1]
  def change
    add_column :columns, :generation_mode, :string, null: false, default: "default"
    add_index :columns, :generation_mode
  end
end
