# In development an unknown API key registers its app on first contact, so a
# fresh agent shows up without any setup. Disable in production.
Rails.configuration.x.auto_register_apps = ENV.fetch("RUBY_APM_AUTO_REGISTER", Rails.env.development? ? "1" : "0") == "1"
