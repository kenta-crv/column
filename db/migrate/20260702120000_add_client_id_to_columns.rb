class AddClientIdToColumns < ActiveRecord::Migration[6.1]
  def change
    add_reference :columns, :client, foreign_key: true, null: true
  end
end
