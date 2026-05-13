class AddSubGenreToColumns < ActiveRecord::Migration[6.1]
  def change
    add_column :columns, :sub_genre, :string
  end
end
