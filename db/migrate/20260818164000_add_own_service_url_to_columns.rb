class AddOwnServiceUrlToColumns < ActiveRecord::Migration[6.1]
  def change
    add_column :columns, :own_service_url, :string
  end
end
