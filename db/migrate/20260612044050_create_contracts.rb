class CreateContracts < ActiveRecord::Migration[6.1]
  def change
    create_table :contracts do |t|
        t.string :company
        t.string :name
        t.string :tel
        t.string :email
        t.string :address
        t.string :url
        t.string :service
        t.string :period
        t.string :message
      t.timestamps
    end
  end
end
