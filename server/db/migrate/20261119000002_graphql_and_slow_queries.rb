class GraphqlAndSlowQueries < ActiveRecord::Migration[8.0]
  def change
    add_column :tx_rollups, :t_graphql, :float, null: false, default: 0

    add_column :sql_rollups, :hist, :integer, array: true, null: false, default: []
    add_column :sql_rollups, :slow_count, :bigint, null: false, default: 0

    create_table :slow_queries do |t|
      t.bigint :app_id, null: false
      t.datetime :ts, null: false
      t.string :key, null: false
      t.float :duration, null: false
      t.string :tx_type, null: false
      t.string :tx_name, null: false
      t.string :uri
      t.string :hostname
      t.string :location
      t.text :backtrace, array: true, null: false, default: []
      t.text :explain
    end
    add_index :slow_queries, [:app_id, :ts]
    add_index :slow_queries, [:app_id, :key, :ts]

    add_column :sql_statements, :last_explain, :text
    add_column :sql_statements, :last_explain_at, :datetime
  end
end
