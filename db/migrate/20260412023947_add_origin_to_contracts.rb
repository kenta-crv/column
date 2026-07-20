class AddOriginToContracts < ActiveRecord::Migration[6.1]
  def change
    # CreateContracts より先にタイムスタンプがあるため、未作成時はスキップ
    return unless table_exists?(:contracts)

    add_column :contracts, :origin, :string unless column_exists?(:contracts, :origin)
  end
end
