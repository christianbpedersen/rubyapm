# The Rails session (CSRF token, flash, post-login redirect) lives under the
# app's mount point only, like the sign-in cookie, and only over HTTPS in
# production.
Rails.application.config.session_store :cookie_store,
  key: "_rubyapm_session", same_site: :lax, secure: Rails.env.production?,
  path: ENV.fetch("RAILS_RELATIVE_URL_ROOT", "/").presence || "/"
