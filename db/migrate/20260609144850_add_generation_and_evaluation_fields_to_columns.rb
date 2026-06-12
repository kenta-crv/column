class AddGenerationAndEvaluationFieldsToColumns < ActiveRecord::Migration[6.1]
  def change
    add_column :columns, :generation_status, :string, default: 'idle', null: false
    add_column :columns, :quality_score, :float, default: 0.0
    add_column :columns, :evaluation_metrics, :jsonb, default: {}
    
    add_index :columns, :generation_status
  end
end
