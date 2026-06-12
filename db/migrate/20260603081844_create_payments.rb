class CreatePayments < ActiveRecord::Migration[6.1]
  def change
    create_table :payments do |t|
      t.integer :client_id, null: false
      t.integer :amount, null: false
      t.string :status, default: "pending", null: false
      t.text :description
      t.string :stripe_payment_intent_id

      t.timestamps
    end

    add_index :payments, :client_id
    add_index :payments, :status
    add_index :payments, :stripe_payment_intent_id, unique: true
    add_foreign_key :payments, :clients
  end
end
