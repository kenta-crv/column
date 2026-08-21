# frozen_string_literal: true

class AddOwnServiceKeyToColumns < ActiveRecord::Migration[6.1]
  def up
    unless column_exists?(:columns, :own_service_key)
      add_column :columns, :own_service_key, :string
    end
    unless index_exists?(:columns, :own_service_key)
      add_index :columns, :own_service_key
    end
  end

  def down
    remove_index :columns, :own_service_key if index_exists?(:columns, :own_service_key)
    remove_column :columns, :own_service_key if column_exists?(:columns, :own_service_key)
  end
end
