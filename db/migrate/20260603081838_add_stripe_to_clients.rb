class AddStripeToClients < ActiveRecord::Migration[6.1]
  def change
    # DeviseCreateClients より先に走るため、テーブル未作成時はスキップ
    return unless table_exists?(:clients)

    unless column_exists?(:clients, :stripe_customer_id)
      add_column :clients, :stripe_customer_id, :string
    end

    unless index_exists?(:clients, :stripe_customer_id)
      add_index :clients, :stripe_customer_id, unique: true
    end
  end
end
