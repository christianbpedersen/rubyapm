class CreateAlerts < ActiveRecord::Migration[8.0]
  def change
    create_table :alert_policies do |t|
      t.bigint :app_id, null: false
      t.string :name, null: false
      t.string :metric, null: false          # see AlertPolicy::METRICS
      t.string :tx_type, null: false, default: "web"
      t.string :tx_name                      # nil = whole app
      t.string :target                       # e.g. external host for external_avg
      t.string :comparison, null: false, default: "above"
      t.float :threshold, null: false
      t.integer :window_minutes, null: false, default: 5
      t.integer :min_samples, null: false, default: 10
      t.string :webhook_url
      t.boolean :enabled, null: false, default: true
      t.datetime :last_evaluated_at
      t.float :last_value
      t.timestamps
    end
    add_index :alert_policies, :app_id

    create_table :incidents do |t|
      t.bigint :app_id, null: false
      t.bigint :alert_policy_id, null: false
      t.datetime :opened_at, null: false
      t.datetime :closed_at
      t.float :threshold, null: false
      t.float :opened_value
      t.float :peak_value
      t.float :last_value
      t.string :notify_error
      t.timestamps
    end
    add_index :incidents, [:app_id, :opened_at]
    add_index :incidents, :alert_policy_id, unique: true, where: "closed_at IS NULL", name: "idx_one_open_incident_per_policy"
  end
end
