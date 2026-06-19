class AddEmbedFieldsToClients < ActiveRecord::Migration[6.1]
  def change
    add_column :clients, :webhook_url, :string
    add_column :clients, :allowed_genres, :json
    add_column :clients, :embed_settings, :json
  end
end
