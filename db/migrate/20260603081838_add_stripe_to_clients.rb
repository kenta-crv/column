class AddStripeToClients < ActiveRecord::Migration[6.1]
def change
    # stripe_customer_id がまだ存在しない場合のみ追加する
    unless column_exists?(:clients, :stripe_customer_id)
      add_column :clients, :stripe_customer_id, :string
    end

    # インデックスも存在しない場合のみ追加する
    unless index_exists?(:clients, :stripe_customer_id)
      add_index :clients, :stripe_customer_id, unique: true
    end
  end
end
