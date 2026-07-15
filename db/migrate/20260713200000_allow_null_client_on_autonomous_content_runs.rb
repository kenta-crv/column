class AllowNullClientOnAutonomousContentRuns < ActiveRecord::Migration[6.1]
  def change
    change_column_null :autonomous_content_runs, :client_id, true
  end
end
