module ColumnsHelper
  def columns_index_link(genre_key, label_text = nil)
    return unless GenreRegistry.genre_keys.include?(genre_key.to_s)

    text = label_text || "#{genre_key.titleize} コラム一覧"
    link_to text, columns_index_path(genre: genre_key), class: "btn btn-primary"
  end
end
