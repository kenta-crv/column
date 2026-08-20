class AddGenreSuggestionCountToClientUsageLogs < ActiveRecord::Migration[6.1]
  def change
    add_column :client_usage_logs, :genre_suggestion_count, :integer, default: 0, null: false
  end
end
