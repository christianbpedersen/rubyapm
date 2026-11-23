class HistAggregate < ActiveRecord::Migration[8.0]
  def up
    # sum(hist) for integer[] latency histograms, used when compacting minute
    # rollups into hourly ones.
    execute <<~SQL
      CREATE AGGREGATE nf_hist_sum(integer[]) (SFUNC = nf_array_add, STYPE = integer[]);
    SQL
  end

  def down
    execute "DROP AGGREGATE IF EXISTS nf_hist_sum(integer[])"
  end
end
