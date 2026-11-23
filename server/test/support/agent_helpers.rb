require "ruby_apm"

# Builds agent transactions by hand and pushes them through the ingest API.
module AgentHelpers
  # Pretend a segment ran for +ms+ by moving its start back.
  def backdate(segment, ms)
    segment.start -= ms
    segment.active_since -= ms
  end

  def fake_request(name, duration_ms:, sql: [], error: nil, http: nil, custom: nil)
    txn = RubyAPM::Transaction.new(type: :web, name: name, uri: "/#{name.downcase}")
    RubyAPM::Transaction.current = txn
    txn.start_segment("Controller/#{name}", :controller, :c)
    sql.each do |raw, ms, times|
      times.to_i.nonzero? ? nil : (times = 1)
      times.times do
        st = RubyAPM::SqlObfuscator.call(raw)
        seg = txn.start_segment("Database/#{st.table}/#{st.operation.downcase}", :database, :q)
        seg.attrs = { "sql" => st.sql, "key" => st.key }
        backdate(seg, ms)
        txn.finish_segment(:q)
        txn.record_sql(st, ms, "app/controllers/x.rb:1")
        if ms >= 50
          txn.record_slow_query(key: st.key, sql: st.sql, operation: st.operation, table: st.table, duration: ms,
                                ts: Time.now.to_f, location: "app/models/order.rb:12:in `x'", backtrace: ["app/models/order.rb:12:in `x'"],
                                explain: "Seq Scan on orders  (cost=0.00..1834.00 rows=50000 width=64)\n  Filter: (status = ?)")
        end
      end
    end
    if http
      seg = txn.start_segment("External/#{http}/GET", :external, :h)
      backdate(seg, 30)
      txn.finish_segment(:h)
    end
    if custom
      seg = txn.start_segment(custom, :custom, :cu)
      backdate(seg, 5)
      txn.finish_segment(:cu)
    end
    backdate(txn.root, duration_ms)
    txn.error = error
    RubyAPM::Transaction.current = nil
    txn.finish
    RubyAPM.aggregator.record(txn)
  end

  def flush!
    body = nil
    reporter = RubyAPM.reporter
    reporter.define_singleton_method(:post) { |b| body = b; true }
    reporter.flush
    post "/api/v1/ingest", params: body, headers: {
      "Content-Type" => "application/msgpack", "Content-Encoding" => "gzip", "Authorization" => "Bearer nf_test"
    }
    assert_response :accepted
    JSON.parse(response.body)
  end
end
