# Stand-ins for third-party APIs with realistic latency and failure rates.
# Routed by Host header: payments.localhost, inventory.localhost,
# shipping.localhost and email.localhost (all on one port).
require "json"
require "time"

LATENCY = {
  "payments" => [80, 350], "inventory" => [15, 60], "shipping" => [60, 420], "email" => [20, 90]
}.freeze

# POST /incident?seconds=120 makes the payments API five times slower for a
# while, so the simulator can stage an outage worth zooming into.
$incident_until = 0.0
# alerts.localhost receives RubyAPM webhooks; GET /hooks lists the last 50.
$hooks = []
$hooks_lock = Mutex.new

app = lambda do |env|
  service = env["HTTP_HOST"].to_s.split(".").first
  if env["PATH_INFO"] == "/incident"
    seconds = env["QUERY_STRING"][/seconds=(\d+)/, 1].to_i.nonzero? || 120
    $incident_until = Time.now.to_f + seconds
    return [200, { "content-type" => "application/json" }, [{ incident_until: $incident_until }.to_json]]
  end

  if service == "alerts"
    if env["REQUEST_METHOD"] == "POST"
      body = env["rack.input"].read
      entry = { received_at: Time.now.utc.iso8601, body: (JSON.parse(body) rescue body) }
      $hooks_lock.synchronize do
        $hooks << entry
        $hooks.shift while $hooks.size > 50
      end
      return [200, { "content-type" => "application/json" }, ['{"ok":true}']]
    end
    list = $hooks_lock.synchronize { $hooks.dup }
    return [200, { "content-type" => "application/json" }, [JSON.pretty_generate(list)]]
  end

  lo, hi = LATENCY.fetch(service, [5, 20])
  ms = rand(lo..hi)
  ms *= 4 if rand < 0.03 # occasional slow tail
  ms *= 5 if service == "payments" && Time.now.to_f < $incident_until
  sleep ms / 1000.0

  return [502, { "content-type" => "application/json" }, ['{"error":"upstream"}']] if service == "payments" && rand < 0.02

  body = case [service, env["PATH_INFO"]]
         in ["payments", "/charges"] then { id: "ch_#{rand(36**10).to_s(36)}", status: rand < 0.03 ? "declined" : "succeeded" }
         in ["inventory", %r{\A/stock/}] then { stock: rand(0..250) }
         in ["shipping", "/rates"] then { cents: rand(499..2499) }
         in ["email", "/send"] then { queued: true }
         else { ok: true }
         end
  [200, { "content-type" => "application/json" }, [body.to_json]]
end

run app
