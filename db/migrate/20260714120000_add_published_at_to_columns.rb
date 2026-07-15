class AddPublishedAtToColumns < ActiveRecord::Migration[6.1]
  def up
    add_column :columns, :published_at, :datetime
    add_index :columns, :published_at

    # 既存の生成済み記事は後方互換のため「公開済み」として扱う。
    # このマイグレーション以降に生成される記事は、手動で公開するまで公開対象にならない。
    execute <<~SQL
      UPDATE columns
      SET published_at = updated_at
      WHERE published_at IS NULL
        AND body IS NOT NULL
        AND TRIM(body) != ''
    SQL
  end

  def down
    remove_index :columns, :published_at if index_exists?(:columns, :published_at)
    remove_column :columns, :published_at
  end
end
