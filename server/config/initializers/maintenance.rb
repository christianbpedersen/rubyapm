# Background work inside the web process, so a single `rails server` is a
# complete installation:
#   - alert evaluation every minute
#   - hourly compaction and pruning
# Disable with RUBY_APM_MAINTENANCE=0 (e.g. when running
# `rails rubyapm:maintain` and `rails rubyapm:alerts` from cron instead).
Rails.application.config.after_initialize do
  next unless defined?(Rails::Server) && ENV.fetch("RUBY_APM_MAINTENANCE", "1") == "1"

  every = lambda do |name, interval, initial_delay, &work|
    Thread.new do
      Thread.current.name = name
      sleep initial_delay
      loop do
        started = Time.now
        begin
          Rails.application.executor.wrap { work.call }
        rescue StandardError => e
          Rails.logger.error("[#{name}] #{e.class}: #{e.message}")
        end
        sleep [interval - (Time.now - started), 1].max
      end
    end
  end

  # Each run is a RubyAPM job transaction when the server monitors itself.
  every.call("rubyapm-alerts", 60, 20) { RubyAPM.in_transaction("Background/AlertEvaluator") { AlertEvaluator.run } }
  every.call("rubyapm-maintenance", 3600, 60) { RubyAPM.in_transaction("Background/Maintenance") { Maintenance.run } }
end
