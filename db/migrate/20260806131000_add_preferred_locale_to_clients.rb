class AddPreferredLocaleToClients < ActiveRecord::Migration[6.1]
  def change
    add_column :clients, :preferred_locale, :string, null: false, default: "ja"
  end
end
