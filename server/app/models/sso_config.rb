require "onelogin/ruby-saml"

# SAML single sign-on settings: one row, edited by admins on the SSO page.
# The IdP's metadata (entity ID, SSO URL, signing certificate) is stored as
# fetched, so sign-in never depends on reaching the metadata URL.
class SsoConfig < ApplicationRecord
  PASSWORD_LOGIN = %w[everyone admins].freeze
  METADATA_LIMIT = 512.kilobytes

  class MetadataError < StandardError; end

  validates :button_label, presence: true, length: { maximum: 40 }
  validates :password_login, inclusion: { in: PASSWORD_LOGIN }
  validate :metadata_is_usable, if: -> { enabled? || idp_metadata_xml.present? }

  normalizes :allowed_domains, with: ->(list) { Array(list).flat_map { |d| d.to_s.split(/[\s,]+/) }.map { |d| d.strip.downcase.delete_prefix("@") }.reject(&:blank?).uniq }

  def self.current = first_or_create!

  def self.enabled? = current.enabled? && current.idp_metadata_xml.present?

  # Parsed IdP settings (entity ID, SSO URL, certificates) for ruby-saml.
  def idp
    @idp ||= OneLogin::RubySaml::IdpMetadataParser.new.parse_to_hash(idp_metadata_xml.to_s)
  end

  def idp_certificates
    certs = idp[:idp_cert_multi]&.dig(:signing).presence || [idp[:idp_cert]].compact
    certs.filter_map { |pem| OpenSSL::X509::Certificate.new(OneLogin::RubySaml::Utils.format_cert(pem)) rescue nil }
  end

  def fetch_metadata!
    uri = URI.parse(idp_metadata_url.to_s)
    raise MetadataError, "Metadata URL must be https" unless uri.is_a?(URI::HTTPS) && uri.host.present?

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.get(uri.request_uri) }
    raise MetadataError, "Fetching metadata failed: HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)
    raise MetadataError, "Metadata is larger than #{METADATA_LIMIT / 1024} KB" if res.body.bytesize > METADATA_LIMIT

    @idp = nil
    self.idp_metadata_xml = res.body
  rescue URI::InvalidURIError, SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
    raise MetadataError, "Fetching metadata failed: #{e.message}"
  end

  def domain_allowed?(email)
    allowed_domains.empty? || allowed_domains.include?(email.to_s.split("@").last.to_s.downcase)
  end

  def password_login_for?(user) = password_login == "everyone" || !enabled? || user&.admin?

  private

  def metadata_is_usable
    if idp_metadata_xml.blank?
      errors.add(:base, "Add the IdP metadata (URL or XML) before enabling single sign-on")
    elsif idp[:idp_sso_service_url].blank? || idp_certificates.empty?
      errors.add(:base, "The metadata has no SSO URL or signing certificate")
    end
  rescue StandardError => e
    errors.add(:base, "The metadata can't be read: #{e.message.truncate(200)}")
  end
end
