# Folds one agent payload into the rollup tables. Payloads are already
# aggregated per minute by the agent, so a busy app sends a few hundred rows
# every flush regardless of its request rate. Each table is written with a
# single multi-row INSERT .. ON CONFLICT that adds to existing minute rows.
class Ingestor
  CATEGORIES = %w[middleware controller view activerecord database external cache custom job graphql].freeze
  HIST_SIZE = 56
  MAX_NAME = 255

  class InvalidPayload < StandardError; end

  attr_reader :counts

  def initialize(app, doc, bytes: 0)
    @app = app
    @doc = doc
    @bytes = bytes
    @counts = Hash.new(0)
  end

  def call
    raise InvalidPayload, "unsupported payload version" unless @doc.is_a?(Hash) && @doc["v"] == 1

    tx_rows = {}
    seg_rows = {}
    sql_rows = {}
    statements = {}
    err_rows = {}
    groups = {}

    record_deployment # outside the transaction: it must not hold a lock shared by every process

    ActiveRecord::Base.transaction do
      fresh_buckets.each do |bucket|
        ts = Time.at(bucket["ts"].to_i).utc
        Array(bucket["transactions"]).each { |t| merge_tx(tx_rows, seg_rows, ts, t) }
        Array(bucket["sql"]).each { |s| merge_sql(sql_rows, statements, ts, s) }
        Array(bucket["errors"]).each { |e| merge_error(err_rows, groups, ts, e) }
      end

      upsert_hosts
      upsert(TxRollup, tx_rows.values, %i[app_id ts tx_type name], rollup_merge("tx_rollups"))
      upsert(AppRollup, app_rows(tx_rows), %i[app_id ts tx_type], rollup_merge("app_rollups"))
      upsert(SegmentRollup, seg_rows.values, %i[app_id ts tx_type tx_name name], <<~SQL)
        count = segment_rollups.count + EXCLUDED.count, txns = segment_rollups.txns + EXCLUDED.txns,
        total = segment_rollups.total + EXCLUDED.total, excl = segment_rollups.excl + EXCLUDED.excl,
        min = LEAST(segment_rollups.min, EXCLUDED.min), max = GREATEST(segment_rollups.max, EXCLUDED.max)
      SQL
      upsert(SqlStatement, statements.values, %i[app_id key], <<~SQL)
        last_seen_at = EXCLUDED.last_seen_at, location = COALESCE(EXCLUDED.location, sql_statements.location)
      SQL
      upsert(SqlRollup, sql_rows.values, %i[app_id ts tx_type tx_name key], <<~SQL)
        count = sql_rollups.count + EXCLUDED.count, txns = sql_rollups.txns + EXCLUDED.txns,
        total = sql_rollups.total + EXCLUDED.total, min = LEAST(sql_rollups.min, EXCLUDED.min),
        max = GREATEST(sql_rollups.max, EXCLUDED.max), max_per_tx = GREATEST(sql_rollups.max_per_tx, EXCLUDED.max_per_tx),
        hist = nf_array_add(sql_rollups.hist, EXCLUDED.hist), slow_count = sql_rollups.slow_count + EXCLUDED.slow_count
      SQL
      upsert(ErrorGroup, groups.values, %i[app_id fingerprint], <<~SQL)
        total_count = error_groups.total_count + EXCLUDED.total_count,
        last_seen_at = GREATEST(error_groups.last_seen_at, EXCLUDED.last_seen_at),
        last_tx_name = EXCLUDED.last_tx_name, last_uri = EXCLUDED.last_uri, message = EXCLUDED.message
      SQL
      upsert(ErrorRollup, err_rows.values, %i[app_id ts fingerprint tx_type tx_name], <<~SQL)
        count = error_rollups.count + EXCLUDED.count
      SQL
      insert_traces
      insert_slow_queries(statements)
      upsert_runtime
      # Apdex is scored by the agent, so the app's T must match what it used.
      attrs = { last_seen_at: Time.current }
      attrs[:apdex_t] = @doc["apdex_t"].to_f if @doc["apdex_t"].to_f.positive?
      @app.update_columns(attrs)
    end
    self
  end

  private

  def rollup_merge(t)
    <<~SQL
      count = #{t}.count + EXCLUDED.count, total = #{t}.total + EXCLUDED.total,
      min = LEAST(#{t}.min, EXCLUDED.min), max = GREATEST(#{t}.max, EXCLUDED.max),
      sumsq = #{t}.sumsq + EXCLUDED.sumsq, errors_count = #{t}.errors_count + EXCLUDED.errors_count,
      apdex_s = #{t}.apdex_s + EXCLUDED.apdex_s, apdex_t = #{t}.apdex_t + EXCLUDED.apdex_t,
      apdex_f = #{t}.apdex_f + EXCLUDED.apdex_f, queue_total = #{t}.queue_total + EXCLUDED.queue_total,
      #{CATEGORIES.map { |c| "t_#{c} = #{t}.t_#{c} + EXCLUDED.t_#{c}" }.join(', ')},
      hist = nf_array_add(#{t}.hist, EXCLUDED.hist)
    SQL
  end

  SUMMED = %i[count total sumsq errors_count apdex_s apdex_t apdex_f queue_total].freeze

  # Per app/minute/type totals across all transaction names.
  def app_rows(tx_rows)
    tx_rows.values.group_by { |r| [r[:ts], r[:tx_type]] }.map do |(ts, type), rows|
      row = { app_id: @app.id, ts: ts, tx_type: type, min: rows.filter_map { |r| r[:min] }.min, max: rows.filter_map { |r| r[:max] }.max,
              hist: rows.map { |r| r[:hist] }.transpose.map(&:sum) }
      (SUMMED + CATEGORIES.map { |c| :"t_#{c}" }).each { |k| row[k] = rows.sum { |r| r[k] } }
      row
    end
  end

  def upsert(model, rows, unique_by, on_duplicate)
    return if rows.empty?

    rows.each_slice(1_000) do |slice|
      model.upsert_all(slice, unique_by: unique_by, on_duplicate: Arel.sql(on_duplicate), record_timestamps: false)
    end
    @counts[model.table_name] += rows.size
  end

  def merge_tx(tx_rows, seg_rows, ts, t)
    type = t["type"].to_s
    name = clip(t["name"])
    key = [ts, type, name]
    row = tx_rows[key] ||= {
      app_id: @app.id, ts: ts, tx_type: type, name: name, count: 0, total: 0.0, min: nil, max: nil, sumsq: 0.0,
      errors_count: 0, apdex_s: 0, apdex_t: 0, apdex_f: 0, queue_total: 0.0, hist: Array.new(HIST_SIZE, 0),
      **CATEGORIES.to_h { |c| [:"t_#{c}", 0.0] }
    }
    row[:count] += t["count"].to_i
    row[:total] += t["total"].to_f
    row[:min] = [row[:min], t["min"]&.to_f].compact.min
    row[:max] = [row[:max], t["max"]&.to_f].compact.max
    row[:sumsq] += t["sumsq"].to_f
    row[:errors_count] += t["errors"].to_i
    s, tol, f = Array(t["apdex"])
    row[:apdex_s] += s.to_i
    row[:apdex_t] += tol.to_i
    row[:apdex_f] += f.to_i
    row[:queue_total] += t["queue"].to_f
    (t["breakdown"] || {}).each do |cat, ms|
      col = :"t_#{cat}"
      row[col] += ms.to_f if row.key?(col)
    end
    (t["hist"] || {}).each do |i, c|
      i = i.to_i
      row[:hist][i] += c.to_i if i.between?(0, HIST_SIZE - 1)
    end

    Array(t["segments"]).each do |s|
      sname = clip(s["name"])
      seg = seg_rows[[ts, type, name, sname]] ||= {
        app_id: @app.id, ts: ts, tx_type: type, tx_name: name, name: sname, category: s["cat"].to_s,
        count: 0, txns: 0, total: 0.0, excl: 0.0, min: nil, max: nil
      }
      seg[:count] += s["count"].to_i
      seg[:txns] += s["txns"].to_i
      seg[:total] += s["total"].to_f
      seg[:excl] += s["excl"].to_f
      seg[:min] = [seg[:min], s["min"]&.to_f].compact.min
      seg[:max] = [seg[:max], s["max"]&.to_f].compact.max
    end
  end

  def merge_sql(sql_rows, statements, ts, s)
    key = s["key"].to_s
    return if key.empty?

    statements[key] ||= {
      app_id: @app.id, key: key, sql: s["sql"].to_s, operation: s["op"], table_name: s["table"],
      location: s["location"], first_seen_at: ts, last_seen_at: ts
    }
    statements[key][:location] ||= s["location"]
    statements[key][:last_seen_at] = [statements[key][:last_seen_at], ts].max

    type = s["tx_type"].to_s
    name = clip(s["tx"])
    row = sql_rows[[ts, type, name, key]] ||= {
      app_id: @app.id, ts: ts, tx_type: type, tx_name: name, key: key,
      count: 0, txns: 0, total: 0.0, min: nil, max: nil, max_per_tx: 0, hist: Array.new(HIST_SIZE, 0), slow_count: 0
    }
    row[:count] += s["count"].to_i
    row[:txns] += s["txns"].to_i
    row[:total] += s["total"].to_f
    row[:min] = [row[:min], s["min"]&.to_f].compact.min
    row[:max] = [row[:max], s["max"]&.to_f].compact.max
    row[:max_per_tx] = [row[:max_per_tx], s["max_per_tx"].to_i].max
    row[:slow_count] += s["slow"].to_i
    (s["hist"] || {}).each do |i, c|
      i = i.to_i
      row[:hist][i] += c.to_i if i.between?(0, HIST_SIZE - 1)
    end
  end

  def merge_error(err_rows, groups, ts, e)
    klass = e["class"].to_s.presence || "Error"
    message = e["message"].to_s
    fingerprint = Digest::MD5.hexdigest("#{klass}|#{normalize_message(message)}|#{Array(e['backtrace']).first}")
    type = e["tx_type"].to_s
    name = clip(e["tx"])
    count = e["count"].to_i
    last = e["last_at"] ? Time.at(e["last_at"].to_f).utc : ts

    group = groups[fingerprint] ||= {
      app_id: @app.id, fingerprint: fingerprint, error_class: klass, message: message,
      backtrace: Array(e["backtrace"]).map(&:to_s), total_count: 0, first_seen_at: ts, last_seen_at: last,
      last_tx_name: name, last_uri: e["uri"]
    }
    group[:total_count] += count
    group[:last_seen_at] = [group[:last_seen_at], last].max

    row = err_rows[[ts, fingerprint, type, name]] ||= {
      app_id: @app.id, ts: ts, fingerprint: fingerprint, tx_type: type, tx_name: name, count: 0
    }
    row[:count] += count
  end

  def insert_traces
    rows = Array(@doc["traces"]).map do |t|
      {
        app_id: @app.id, ts: Time.at(t["ts"].to_f).utc, tx_type: t["tx_type"].to_s, tx_name: clip(t["tx"]),
        duration: t["duration"].to_f, uri: t["uri"]&.to_s&.first(1000), status: t["status"], error_class: t["error"],
        segment_count: t["segments"], hostname: @doc["host"], breakdown: t["breakdown"] || {},
        tree: t["tree"] || [], attrs: t["attributes"] || {}
      }
    end
    return if rows.empty?

    Trace.insert_all(rows, record_timestamps: false)
    @counts["traces"] += rows.size
  end

  def insert_slow_queries(statements)
    samples = Array(@doc["slow_queries"])
    return if samples.empty?

    rows = samples.filter_map do |q|
      key = q["key"].to_s
      next if key.empty?

      # A statement can be slow before its first rollup row arrives.
      statements[key] ||= { app_id: @app.id, key: key, sql: q["sql"].to_s, operation: q["op"], table_name: q["table"],
                            location: q["location"], first_seen_at: Time.current, last_seen_at: Time.current }
      {
        app_id: @app.id, ts: Time.at(q["ts"].to_f).utc, key: key, duration: q["duration"].to_f,
        tx_type: q["tx_type"].to_s, tx_name: clip(q["tx"]), uri: q["uri"]&.to_s&.first(1000), hostname: @doc["host"],
        location: q["location"], backtrace: Array(q["backtrace"]).map(&:to_s).first(20), explain: q["explain"]
      }
    end
    upsert(SqlStatement, statements.values.select { |st| rows.any? { |r| r[:key] == st[:key] } }, %i[app_id key],
           "last_seen_at = GREATEST(sql_statements.last_seen_at, EXCLUDED.last_seen_at)")
    SlowQuery.insert_all(rows, record_timestamps: false)
    rows.select { |r| r[:explain].present? && !r[:explain].match?(/\AEXPLAIN (failed|skipped)/) }.each do |r|
      SqlStatement.where(app_id: @app.id, key: r[:key]).update_all(last_explain: r[:explain], last_explain_at: r[:ts])
    end
    @counts["slow_queries"] += rows.size
  end

  # Buckets this server has not stored before. Recording the ids in the same
  # transaction as the rollups makes a retried payload a no-op.
  def fresh_buckets
    buckets = Array(@doc["buckets"]).select { |b| b.is_a?(Hash) }
    uuid = ->(b) { b["id"].to_s.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/i) ? b["id"].to_s.downcase : nil }
    ids = buckets.filter_map(&uuid)
    return buckets if ids.empty?

    now = Time.current
    inserted = IngestedBucket.insert_all(ids.uniq.map { |id| { app_id: @app.id, bucket_id: id, received_at: now } },
                                         unique_by: %i[app_id bucket_id], returning: %i[bucket_id]).rows.flatten.to_set
    @counts["duplicate_buckets"] = ids.size - inserted.size if inserted.size < ids.size
    buckets.select { |b| (id = uuid.call(b)).nil? || inserted.include?(id) }
  end

  # The first process to report a revision marks when it was deployed.
  def record_deployment
    revision = @doc["revision"].to_s.first(64)
    return if revision.empty?

    at = @doc["booted_at"] ? Time.at(@doc["booted_at"].to_f).utc : Time.current
    known = Deployment.where(app_id: @app.id, revision: revision).pick(:deployed_at)
    return if known && known <= at
    Deployment.upsert({ app_id: @app.id, revision: revision, deployed_at: at, hostname: @doc["host"] },
                      unique_by: %i[app_id revision],
                      on_duplicate: Arel.sql("deployed_at = LEAST(deployments.deployed_at, EXCLUDED.deployed_at)"),
                      record_timestamps: false)
  end

  def upsert_runtime
    r = @doc["runtime"]
    return unless r.is_a?(Hash)

    ts = Time.at((@doc["sent_at"].to_f / 60).floor * 60).utc
    row = { app_id: @app.id, ts: ts, hostname: @doc["host"].to_s.presence || "unknown", pid: @doc["pid"].to_i,
            elapsed_ms: r["elapsed_ms"].to_f, cpu_ms: r["cpu_ms"].to_f, gc_time_ms: r["gc_time_ms"].to_f,
            gc_count: r["gc_count"].to_i, gc_major: r["gc_major"].to_i, allocations: r["allocations"].to_i,
            rss_mb: r["rss_mb"], heap_live_slots: r["heap_live_slots"], threads: r["threads"],
            db_pool_size: r["db_pool_size"], db_pool_busy: r["db_pool_busy"], db_pool_waiting: r["db_pool_waiting"] }
    RuntimeRollup.upsert(row, unique_by: %i[app_id ts hostname pid], record_timestamps: false, on_duplicate: Arel.sql(<<~SQL))
      elapsed_ms = runtime_rollups.elapsed_ms + EXCLUDED.elapsed_ms, cpu_ms = runtime_rollups.cpu_ms + EXCLUDED.cpu_ms,
      gc_time_ms = runtime_rollups.gc_time_ms + EXCLUDED.gc_time_ms, gc_count = runtime_rollups.gc_count + EXCLUDED.gc_count,
      gc_major = runtime_rollups.gc_major + EXCLUDED.gc_major, allocations = runtime_rollups.allocations + EXCLUDED.allocations,
      rss_mb = GREATEST(runtime_rollups.rss_mb, EXCLUDED.rss_mb), heap_live_slots = EXCLUDED.heap_live_slots,
      threads = GREATEST(runtime_rollups.threads, EXCLUDED.threads), db_pool_size = EXCLUDED.db_pool_size,
      db_pool_busy = GREATEST(runtime_rollups.db_pool_busy, EXCLUDED.db_pool_busy),
      db_pool_waiting = GREATEST(runtime_rollups.db_pool_waiting, EXCLUDED.db_pool_waiting)
    SQL
    @counts["runtime_rollups"] += 1
  end

  def upsert_hosts
    now = Time.current
    Host.upsert(
      { app_id: @app.id, hostname: @doc["host"].to_s.presence || "unknown", pid: @doc["pid"].to_i,
        environment: @doc["env"], agent_version: @doc["agent"], rails_version: @doc["rails"],
        ruby_version: @doc["ruby"], payloads: 1, bytes: @bytes, last_seen_at: now, created_at: now, updated_at: now },
      unique_by: %i[app_id hostname pid],
      on_duplicate: Arel.sql("payloads = hosts.payloads + 1, bytes = hosts.bytes + EXCLUDED.bytes, " \
                             "last_seen_at = EXCLUDED.last_seen_at, updated_at = EXCLUDED.updated_at, " \
                             "agent_version = EXCLUDED.agent_version"),
      record_timestamps: false
    )
  end

  # Group "Couldn't find User with 'id'=123" with "... 'id'=456".
  def normalize_message(message)
    message.gsub(/\b0x\h+\b/, "0x?").gsub(/\d+/, "?").first(300)
  end

  def clip(name)
    name.to_s.first(MAX_NAME).presence || "unknown"
  end
end
