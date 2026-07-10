class AddArticleCreationCountsToClientUsageLogs < ActiveRecord::Migration[6.1]
  class ClientUsageLog < ApplicationRecord
    self.table_name = "client_usage_logs"
  end

  class Client < ApplicationRecord
    self.table_name = "clients"
    has_many :client_usage_logs, class_name: "AddArticleCreationCountsToClientUsageLogs::ClientUsageLog"
    has_many :columns, class_name: "AddArticleCreationCountsToClientUsageLogs::Column"
  end

  class Column < ApplicationRecord
    self.table_name = "columns"
    belongs_to :client, class_name: "AddArticleCreationCountsToClientUsageLogs::Client", optional: true
  end

  def up
    add_column :client_usage_logs, :pillar_created_count, :integer, null: false, default: 0
    add_column :client_usage_logs, :child_created_count, :integer, null: false, default: 0

    Client.find_each do |client|
      period = client.read_attribute(:subscription_plan) == "trial" && client.read_attribute(:trial_ends_at).present? ? "trial" : Time.current.strftime("%Y-%m")
      period_start = if period == "trial"
                       client.read_attribute(:trial_ends_at) - 10.days
                     else
                       Time.current.beginning_of_month
                     end

      scope = client.columns.where("created_at >= ?", period_start)
      pillar_count = scope.where(article_type: "pillar").count
      child_count = scope.where.not(article_type: "pillar").count

      log = client.client_usage_logs.find_or_create_by!(period: period)
      log.update_columns(
        pillar_created_count: [log.pillar_created_count, pillar_count].max,
        child_created_count: [log.child_created_count, child_count].max
      )
    end
  end

  def down
    remove_column :client_usage_logs, :pillar_created_count
    remove_column :client_usage_logs, :child_created_count
  end
end
