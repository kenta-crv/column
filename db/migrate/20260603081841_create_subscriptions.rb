class CreateSubscriptions < ActiveRecord::Migration[6.1]
  def change
    return if table_exists?(:subscriptions)

    create_table :subscriptions do |t|
      t.integer :client_id, null: false
      t.string :plan_type, null: false
      t.string :status, default: "active", null: false
      t.datetime :trial_ends_at
      t.string :stripe_subscription_id

      t.timestamps
    end

    add_index :subscriptions, :client_id
    add_index :subscriptions, :status
    add_index :subscriptions, :stripe_subscription_id, unique: true
    # clients テーブル作成前に走る場合があるため FK は条件付き
    add_foreign_key :subscriptions, :clients if table_exists?(:clients)
  end
end
