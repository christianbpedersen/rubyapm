class BigintHistogramsAndBucketIds < ActiveRecord::Migration[8.0]
  HIST_TABLES = %w[tx_rollups app_rollups sql_rollups].freeze

  def up
    # Multi-day sums of a busy app exceed 2^31 per bucket; use 64-bit counts.
    execute "DROP AGGREGATE IF EXISTS nf_hist_sum(integer[])"
    HIST_TABLES.each do |t|
      execute "ALTER TABLE #{t} ALTER COLUMN hist DROP DEFAULT, ALTER COLUMN hist TYPE bigint[] USING hist::bigint[], ALTER COLUMN hist SET DEFAULT '{}'"
    end
    execute "DROP FUNCTION IF EXISTS nf_array_add(integer[], integer[])"
    execute <<~SQL
      CREATE OR REPLACE FUNCTION nf_array_add(a bigint[], b bigint[]) RETURNS bigint[]
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
    execute "CREATE AGGREGATE nf_hist_sum(bigint[]) (SFUNC = nf_array_add, STYPE = bigint[])"

    # Buckets already folded in, so an agent retrying after a timeout
    # (the server committed, the response was lost) cannot double count.
    create_table :ingested_buckets, id: false do |t|
      t.bigint :app_id, null: false
      t.uuid :bucket_id, null: false
      t.datetime :received_at, null: false
    end
    add_index :ingested_buckets, [:app_id, :bucket_id], unique: true
    add_index :ingested_buckets, :received_at
  end

  def down
    drop_table :ingested_buckets
    raise ActiveRecord::IrreversibleMigration, "histograms stay bigint[]"
  end
end
