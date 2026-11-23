class CreateDeployments < ActiveRecord::Migration[8.0]
  def change
    create_table :deployments do |t|
      t.bigint :app_id, null: false
      t.string :revision, null: false
      t.datetime :deployed_at, null: false
      t.string :hostname
    end
    add_index :deployments, [:app_id, :revision], unique: true
    add_index :deployments, [:app_id, :deployed_at]
  end
end
