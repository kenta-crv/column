class AddContentUpdatedAtToColumns < ActiveRecord::Migration[6.1]
  def up
    add_column :columns, :content_updated_at, :datetime
    add_index :columns, :content_updated_at

    # 過去の本文変更時刻は残っていない。公開日、無ければ作成日で初期化する。
    execute <<~SQL
      UPDATE columns
      SET content_updated_at = COALESCE(published_at, created_at)
      WHERE content_updated_at IS NULL
    SQL
  end

  def down
    remove_index :columns, :content_updated_at if index_exists?(:columns, :content_updated_at)
    remove_column :columns, :content_updated_at
  end
end
