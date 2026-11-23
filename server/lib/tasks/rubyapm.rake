namespace :rubyapm do
  desc "Compact minute rollups older than COMPACT_AFTER_HOURS (24) into hourly rows and prune data older than RETENTION_DAYS (8)"
  task maintain: :environment do
    Maintenance.run
  end

  desc "Delete data older than RETENTION_DAYS (default 8)"
  task prune: :environment do
    Maintenance.prune(Maintenance::RETENTION_DAYS.days.ago)
  end
end

namespace :rubyapm do
  desc "Evaluate alert policies once (run every minute from cron when RUBY_APM_MAINTENANCE=0)"
  task alerts: :environment do
    AlertEvaluator.run
  end
end

namespace :rubyapm do
  desc "Create or update the app named RUBY_APM_BOOTSTRAP_APP with key RUBY_APM_BOOTSTRAP_API_KEY (used by deployments)"
  task bootstrap: :environment do
    name = ENV["RUBY_APM_BOOTSTRAP_APP"].to_s.strip
    key = ENV["RUBY_APM_BOOTSTRAP_API_KEY"].to_s.strip
    next puts("[bootstrap] RUBY_APM_BOOTSTRAP_APP / _API_KEY not set; nothing to do") if name.empty? || key.empty?

    app = App.find_or_initialize_by(name: name)
    app.api_key = key
    app.save!
    puts "[bootstrap] app #{app.name.inspect} (id #{app.id}) ready"
  end
end
