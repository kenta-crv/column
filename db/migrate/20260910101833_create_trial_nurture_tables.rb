# frozen_string_literal: true

class CreateTrialNurtureTables < ActiveRecord::Migration[6.1]
  def change
    create_table :client_trial_progresses do |t|
      t.references :client, null: false, foreign_key: true, index: { unique: true }
      t.datetime :genre_setup_at
      t.datetime :first_title_suggestion_at
      t.datetime :first_pillar_created_at
      t.datetime :first_pillar_body_completed_at
      t.datetime :first_child_created_at
      t.datetime :conversion_offer_expires_at
      t.datetime :converted_at

      t.timestamps
    end

    create_table :trial_nurture_email_logs do |t|
      t.references :client, null: false, foreign_key: true
      t.string :kind, null: false
      t.datetime :sent_at, null: false
      t.string :stage_at_send
      t.json :metadata

      t.timestamps
    end

    add_index :trial_nurture_email_logs, %i[client_id kind], unique: true
    add_index :trial_nurture_email_logs, :kind
  end
end
