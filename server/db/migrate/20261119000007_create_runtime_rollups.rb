class CreateRuntimeRollups < ActiveRecord::Migration[8.0]
  def change
    # One row per process per minute. Counters are summed deltas; gauges keep
    # the latest/maximum value seen in the minute.
    create_table :runtime_rollups do |t|
      t.bigint :app_id, null: false
      t.datetime :ts, null: false
      t.string :hostname, null: false
      t.integer :pid, null: false
      t.float :elapsed_ms, null: false, default: 0
      t.float :cpu_ms, null: false, default: 0
      t.float :gc_time_ms, null: false, default: 0
      t.bigint :gc_count, null: false, default: 0
      t.bigint :gc_major, null: false, default: 0
      t.bigint :allocations, null: false, default: 0
      t.float :rss_mb
      t.bigint :heap_live_slots
      t.integer :threads
      t.integer :db_pool_size
      t.integer :db_pool_busy
      t.integer :db_pool_waiting
    end
    add_index :runtime_rollups, [:app_id, :ts, :hostname, :pid], unique: true, name: "idx_runtime_rollups_key"
  end
end
