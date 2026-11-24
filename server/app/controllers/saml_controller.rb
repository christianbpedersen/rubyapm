# SAML 2.0 single sign-on (SP side). OneLogin, or any SAML IdP, posts a
# signed response to /saml/acs; the email in it signs in the matching user,
# or creates one when auto-provisioning allows it. Both SP-initiated
# (button on the login page) and IdP-initiated (app tile) sign-in work.
class SamlController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection only: :acs # the IdP's POST carries no CSRF token; the SAML signature is the proof
  before_action :require_sso, except: :metadata
  layout "auth"

  PENDING = :rapm_saml
  EMAIL_ATTRIBUTES = %w[email Email User.email mail urn:oid:0.9.2342.19200300.100.1.3
                        http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress].freeze
  NAME_ATTRIBUTES = %w[name displayName User.FullName http://schemas.microsoft.com/identity/claims/displayname].freeze
  FIRST_ATTRIBUTES = %w[firstName FirstName first_name User.FirstName givenName http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname].freeze
  LAST_ATTRIBUTES = %w[lastName LastName last_name User.LastName sn surname http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname].freeze

  # SP metadata to register at the IdP (available before SSO is enabled).
  def metadata
    render xml: OneLogin::RubySaml::Metadata.new.generate(settings, true)
  end

  def login
    request_obj = OneLogin::RubySaml::Authrequest.new
    url = request_obj.create(settings)
    # The IdP posts back cross-site, where the Lax session cookie isn't sent;
    # this short-lived cookie carries the request ID and where to go after.
    cookies.signed[PENDING] = { value: { "id" => request_obj.uuid, "return_to" => session[:return_to] }.to_json,
                                expires: 10.minutes, httponly: true, path: "#{cookie_path.chomp('/')}/saml",
                                secure: request.ssl?, same_site: request.ssl? ? :none : :lax }
    redirect_to url, allow_other_host: true
  end

  def acs
    pending = JSON.parse(cookies.signed[PENDING].to_s) rescue {}
    cookies.delete(PENDING, path: "#{cookie_path.chomp('/')}/saml")
    response_obj = OneLogin::RubySaml::Response.new(params[:SAMLResponse].to_s, settings: settings,
                                                    matches_request_id: pending["id"], allowed_clock_drift: 30.seconds)
    return fail_sign_in("the SAML response is invalid", response_obj.errors) unless response_obj.is_valid?
    return fail_sign_in("this SAML response was already used") unless first_use?(response_obj)

    email = saml_email(response_obj)
    return fail_sign_in("the IdP sent no email address") if email.blank?

    config = SsoConfig.current
    user = User.find_by(email: email)
    unless user
      return fail_sign_in("#{email} has no RubyAPM account; ask an admin to add you") unless config.auto_provision?
      return fail_sign_in("#{email.split('@').last} isn't an allowed domain") unless config.domain_allowed?(email)
      user = User.create!(email: email, name: saml_name(response_obj), role: "member")
    end
    user.update_column(:name, saml_name(response_obj)) if user.name.blank? && saml_name(response_obj)

    session[:return_to] = pending["return_to"] if pending["return_to"].present?
    target = after_login_url
    start_session(user)
    user.update_column(:last_sign_in_via, "saml")
    redirect_to target
  end

  private

  def settings = @settings ||= SamlSettings.for("#{request.base_url}#{request.script_name}")

  def require_sso
    redirect_to login_path, alert: "Single sign-on isn't set up." unless SsoConfig.enabled?
  end

  # Each assertion signs in once, even within its validity window.
  def first_use?(response_obj)
    key = "saml-assertion:#{Digest::SHA256.hexdigest(response_obj.assertion_id.to_s)}"
    Rails.cache.write(key, true, unless_exist: true, expires_in: 1.hour) != false
  end

  def saml_email(response_obj)
    attrs = response_obj.attributes
    found = EMAIL_ATTRIBUTES.lazy.map { |a| attrs[a] }.find(&:present?)
    found ||= response_obj.name_id if response_obj.name_id.to_s.include?("@")
    found.to_s.strip.downcase.presence
  end

  def saml_name(response_obj)
    attrs = response_obj.attributes
    full = NAME_ATTRIBUTES.lazy.map { |a| attrs[a] }.find(&:present?)
    first = FIRST_ATTRIBUTES.lazy.map { |a| attrs[a] }.find(&:present?)
    last = LAST_ATTRIBUTES.lazy.map { |a| attrs[a] }.find(&:present?)
    (full.presence || [first, last].compact.join(" ")).to_s.strip.presence&.truncate(100)
  end

  def fail_sign_in(reason, details = [])
    Rails.logger.warn("[saml] sign-in refused: #{reason} #{Array(details).join('; ')}".strip)
    redirect_to login_path, alert: "Single sign-on failed: #{reason}."
  end
end
