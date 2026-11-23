namespace :rubyapm do
  desc "Create a demo app with DAYS (7) of history, replayed from SOURCE_APP's recent minutes with a daily traffic curve"
  task demo_backfill: :environment do
    days = Integer(ENV.fetch("DAYS", 7))
    source = App.find(ENV.fetch("SOURCE_APP", App.order(:id).first.id))
    demo = App.find_or_create_by!(name: "#{source.name} (week of history)") { |a| a.apdex_t = source.apdex_t }
    conn = ActiveRecord::Base.connection

    template = TxRollup.where(app_id: source.id).where(ts: ...1.minute.ago.beginning_of_minute)
                       .distinct.order(ts: :desc).limit(20).pluck(:ts).sort
    abort "source app needs at least 5 minutes of data" if template.size < 5

    [TxRollup, SegmentRollup, SqlRollup, ErrorRollup, Trace, SlowQuery, Deployment].each { |m| m.where(app_id: demo.id).delete_all }
    conn.execute(<<~SQL)
      CREATE OR REPLACE FUNCTION pg_temp.nf_scale(a integer[], f float8) RETURNS integer[] LANGUAGE sql IMMUTABLE AS $$
        SELECT coalesce(array_agg(round(v * f)::int ORDER BY i), '{}') FROM unnest(a) WITH ORDINALITY u(v, i)
      $$;
    SQL

    stop = 1.hour.ago.beginning_of_minute
    start = (stop - days.days).beginning_of_minute
    # minute -> template minute, plus a traffic factor peaking mid-afternoon UTC and lower at weekends.
    plan = <<~SQL
      SELECT m AS ts,
             (ARRAY[#{template.map { |t| conn.quote(t) }.join(',')}]::timestamp[])[1 + (extract(epoch FROM m)::bigint / 60) % #{template.size}] AS src,
             greatest(0.15, (0.55 + 0.45 * sin(2 * pi() * (extract(hour FROM m) + extract(minute FROM m) / 60.0 - 9) / 24))
               * CASE WHEN extract(isodow FROM m) IN (6, 7) THEN 0.6 ELSE 1 END) AS f
      FROM generate_series(#{conn.quote(start)}::timestamp, #{conn.quote(stop)}::timestamp, interval '1 minute') m
    SQL

    cats = Ingestor::CATEGORIES.map { |c| "t_#{c}" }
    copies = {
      "tx_rollups" => ["tx_type, name, count, total, min, max, sumsq, errors_count, apdex_s, apdex_t, apdex_f, queue_total, #{cats.join(', ')}, hist",
                       "r.tx_type, r.name, greatest(1, round(r.count * p.f)), r.total * p.f, r.min, r.max, r.sumsq * p.f, round(r.errors_count * p.f), " \
                       "round(r.apdex_s * p.f), round(r.apdex_t * p.f), round(r.apdex_f * p.f), r.queue_total * p.f, " \
                       "#{cats.map { |c| "r.#{c} * p.f" }.join(', ')}, pg_temp.nf_scale(r.hist, p.f)"],
      "segment_rollups" => ["tx_type, tx_name, name, category, count, txns, total, excl, min, max",
                            "r.tx_type, r.tx_name, r.name, r.category, greatest(1, round(r.count * p.f)), greatest(1, round(r.txns * p.f)), r.total * p.f, r.excl * p.f, r.min, r.max"],
      "sql_rollups" => ["tx_type, tx_name, key, count, txns, total, min, max, max_per_tx, hist, slow_count",
                        "r.tx_type, r.tx_name, r.key, greatest(1, round(r.count * p.f)), greatest(1, round(r.txns * p.f)), r.total * p.f, r.min, r.max, r.max_per_tx, pg_temp.nf_scale(r.hist, p.f), round(r.slow_count * p.f)"],
      "error_rollups" => ["fingerprint, tx_type, tx_name, count", "r.fingerprint, r.tx_type, r.tx_name, greatest(1, round(r.count * p.f))"]
    }

    copies.each do |table, (cols, exprs)|
      t0 = Time.now
      day = start
      total = 0
      while day < stop
        day_end = [day + 1.day, stop].min
        n = conn.exec_update(<<~SQL)
          INSERT INTO #{table} (app_id, ts, #{cols})
          SELECT #{demo.id}, p.ts, #{exprs}
          FROM (#{plan}) p JOIN #{table} r ON r.app_id = #{source.id} AND r.ts = p.src
          WHERE p.ts >= #{conn.quote(day)} AND p.ts < #{conn.quote(day_end)}
          ON CONFLICT DO NOTHING
        SQL
        total += n
        day = day_end
      end
      puts format("%-16s %9d rows in %.1fs", table, total, Time.now - t0)
    end

    SqlStatement.where(app_id: source.id).find_each do |st|
      SqlStatement.find_or_create_by!(app_id: demo.id, key: st.key) do |c|
        c.assign_attributes(st.attributes.except("id", "app_id").merge("first_seen_at" => start))
      end
    end
    ErrorGroup.where(app_id: source.id).find_each do |g|
      ErrorGroup.find_or_create_by!(app_id: demo.id, fingerprint: g.fingerprint) do |c|
        c.assign_attributes(g.attributes.except("id", "app_id").merge("first_seen_at" => start))
      end
    end
    # Traces and slow samples spread over the week so drill-downs have something to open.
    traces = Trace.where(app_id: source.id).order(duration: :desc).limit(200).to_a
    slow = SlowQuery.where(app_id: source.id).order(duration: :desc).limit(200).to_a
    span = (stop - start).to_i
    Trace.insert_all(traces.each_with_index.map { |t, i| t.attributes.except("id").merge("app_id" => demo.id, "ts" => start + (span * i / traces.size)) }) if traces.any?
    SlowQuery.insert_all(slow.each_with_index.map { |q, i| q.attributes.except("id").merge("app_id" => demo.id, "ts" => start + (span * i / slow.size)) }) if slow.any?
    %w[a1b2c3d e4f5a6b 9c8d7e6].each_with_index do |rev, i|
      Deployment.create!(app_id: demo.id, revision: rev, deployed_at: start + (i + 1) * 2.days + 3.hours, hostname: "deploy")
    end
    demo.update!(last_seen_at: Time.current)
    puts "Demo app ##{demo.id}: #{demo.name}"
  end
end
