# In development an unknown API key registers its app on first contact, so a
# fresh agent shows up without any setup. Disable in production.
# Alert webhooks may only reach public addresses, except in tests (local
# receivers) or when explicitly allowed for a private deployment.
Rails.configuration.x.webhooks_allow_private = Rails.env.test? || ENV["RUBY_APM_WEBHOOKS_ALLOW_PRIVATE"] == "1"

Rails.configuration.x.auto_register_apps = ENV.fetch("RUBY_APM_AUTO_REGISTER", Rails.env.development? ? "1" : "0") == "1"
