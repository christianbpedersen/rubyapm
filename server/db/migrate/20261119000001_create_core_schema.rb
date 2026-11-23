class CreateCoreSchema < ActiveRecord::Migration[8.0]
  CATEGORIES = %w[middleware controller view activerecord database external cache custom job].freeze

  def up
    # Element-wise sum for latency histograms merged on upsert and in queries.
    execute <<~SQL
      CREATE OR REPLACE FUNCTION nf_array_add(a integer[], b integer[]) RETURNS integer[]
      LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
        SELECT CASE WHEN a IS NULL THEN b WHEN b IS NULL THEN a ELSE
          ARRAY(SELECT coalesce(a[i], 0) + coalesce(b[i], 0)
                FROM generate_series(1, greatest(array_length(a, 1), array_length(b, 1))) AS i)
        END
      $$;
    SQL

    create_table :apps do |t|
      t.string :name, null: false
      t.string :api_key, null: false
      t.float :apdex_t, null: false, default: 500.0
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :apps, :name, unique: true
    add_index :apps, :api_key, unique: true

    create_table :hosts do |t|
      t.references :app, null: false, foreign_key: true
      t.string :hostname, null: false
      t.integer :pid
      t.string :environment
      t.string :agent_version
      t.string :rails_version
      t.string :ruby_version
      t.bigint :payloads, null: false, default: 0
      t.bigint :bytes, null: false, default: 0
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :hosts, [:app_id, :hostname, :pid], unique: true

    create_table :tx_rollups do |t|
      t.bigint :app_id, null: false
      t.datetime :ts, null: false
      t.string :tx_type, null: false
      t.string :name, null: false
      t.bigint :count, null: false, default: 0
      t.float :total, null: false, default: 0
      t.float :min
      t.float :max
      t.float :sumsq, null: false, default: 0
      t.bigint :errors_count, null: false, default: 0
      t.bigint :apdex_s, null: false, default: 0
      t.bigint :apdex_t, null: false, default: 0
      t.bigint :apdex_f, null: false, default: 0
      t.float :queue_total, null: false, default: 0
      CATEGORIES.each { |c| t.float :"t_#{c}", null: false, default: 0 }
      t.integer :hist, array: true, null: false, default: []
    end
    add_index :tx_rollups, [:app_id, :ts, :tx_type, :name], unique: true, name: "idx_tx_rollups_key"
    add_index :tx_rollups, [:app_id, :tx_type, :name, :ts], name: "idx_tx_rollups_name"

    create_table :segment_rollups do |t|
      t.bigint :app_id, null: false
      t.datetime :ts, null: false
      t.string :tx_type, null: false
      t.string :tx_name, null: false
      t.string :name, null: false
      t.string :category, null: false
      t.bigint :count, null: false, default: 0
      t.bigint :txns, null: false, default: 0
      t.float :total, null: false, default: 0
      t.float :excl, null: false, default: 0
      t.float :min
      t.float :max
    end
    add_index :segment_rollups, [:app_id, :ts, :tx_type, :tx_name, :name], unique: true, name: "idx_segment_rollups_key"
    add_index :segment_rollups, [:app_id, :tx_type, :tx_name, :ts], name: "idx_segment_rollups_tx"
    add_index :segment_rollups, [:app_id, :category, :ts], name: "idx_segment_rollups_cat"
    add_index :segment_rollups, [:app_id, :name, :ts], name: "idx_segment_rollups_name"

    create_table :sql_statements do |t|
      t.bigint :app_id, null: false
      t.string :key, null: false
      t.text :sql, null: false
      t.string :operation
      t.string :table_name
      t.string :location
      t.datetime :first_seen_at
      t.datetime :last_seen_at
    end
    add_index :sql_statements, [:app_id, :key], unique: true

    create_table :sql_rollups do |t|
      t.bigint :app_id, null: false
      t.datetime :ts, null: false
      t.string :tx_type, null: false
      t.string :tx_name, null: false
      t.string :key, null: false
      t.bigint :count, null: false, default: 0
      t.bigint :txns, null: false, default: 0
      t.float :total, null: false, default: 0
      t.float :min
      t.float :max
      t.integer :max_per_tx, null: false, default: 0
    end
    add_index :sql_rollups, [:app_id, :ts, :tx_type, :tx_name, :key], unique: true, name: "idx_sql_rollups_key"
    add_index :sql_rollups, [:app_id, :key, :ts], name: "idx_sql_rollups_stmt"
    add_index :sql_rollups, [:app_id, :tx_type, :tx_name, :ts], name: "idx_sql_rollups_tx"

    create_table :error_groups do |t|
      t.bigint :app_id, null: false
      t.string :fingerprint, null: false
      t.string :error_class, null: false
      t.text :message
      t.text :backtrace, array: true, default: []
      t.string :last_tx_name
      t.string :last_uri
      t.bigint :total_count, null: false, default: 0
      t.datetime :first_seen_at
      t.datetime :last_seen_at
    end
    add_index :error_groups, [:app_id, :fingerprint], unique: true

    create_table :error_rollups do |t|
      t.bigint :app_id, null: false
      t.datetime :ts, null: false
      t.string :fingerprint, null: false
      t.string :tx_type, null: false
      t.string :tx_name, null: false
      t.bigint :count, null: false, default: 0
    end
    add_index :error_rollups, [:app_id, :ts, :fingerprint, :tx_type, :tx_name], unique: true, name: "idx_error_rollups_key"
    add_index :error_rollups, [:app_id, :fingerprint, :ts], name: "idx_error_rollups_fp"

    create_table :traces do |t|
      t.bigint :app_id, null: false
      t.datetime :ts, null: false
      t.string :tx_type, null: false
      t.string :tx_name, null: false
      t.float :duration, null: false
      t.string :uri
      t.integer :status
      t.string :error_class
      t.integer :segment_count
      t.string :hostname
      t.jsonb :breakdown, null: false, default: {}
      t.jsonb :tree, null: false, default: []
      t.jsonb :attrs, null: false, default: {}
    end
    add_index :traces, [:app_id, :ts]
    add_index :traces, [:app_id, :tx_type, :tx_name, :ts]
  end

  def down
    %i[traces error_rollups error_groups sql_rollups sql_statements segment_rollups tx_rollups hosts apps].each { |t| drop_table t }
    execute "DROP FUNCTION IF EXISTS nf_array_add(integer[], integer[])"
  end
end
