class AppRollups < ActiveRecord::Migration[8.0]
  CATEGORIES = %w[middleware controller view activerecord database external cache custom job graphql].freeze

  def up
    # PL/pgSQL adds in place; ~3x faster than the SQL version built on
    # generate_series when summing thousands of histograms.
    execute <<~SQL
      CREATE OR REPLACE FUNCTION nf_array_add(a integer[], b integer[]) RETURNS integer[]
      LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
      DECLARE i int;
      BEGIN
        IF a IS NULL OR cardinality(a) = 0 THEN RETURN b; END IF;
        IF b IS NULL OR cardinality(b) = 0 THEN RETURN a; END IF;
        FOR i IN 1..cardinality(b) LOOP
          a[i] := coalesce(a[i], 0) + coalesce(b[i], 0);
        END LOOP;
        RETURN a;
      END $$;
    SQL

    # Totals per app/minute/type: what overview charts read, instead of
    # summing every transaction name.
    create_table :app_rollups do |t|
      t.bigint :app_id, null: false
      t.datetime :ts, null: false
      t.string :tx_type, null: false
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
    add_index :app_rollups, [:app_id, :ts, :tx_type], unique: true

    cols = %w[count total sumsq errors_count apdex_s apdex_t apdex_f queue_total] + CATEGORIES.map { |c| "t_#{c}" }
    execute <<~SQL
      INSERT INTO app_rollups (app_id, ts, tx_type, #{cols.join(', ')}, min, max, hist)
      SELECT app_id, ts, tx_type, #{cols.map { |c| "sum(#{c})" }.join(', ')}, min(min), max(max), nf_hist_sum(hist)
      FROM tx_rollups GROUP BY app_id, ts, tx_type
    SQL
  end

  def down
    drop_table :app_rollups
  end
end
