# An MCP client registered through OAuth dynamic client registration
# (RFC 7591). All clients are public: they prove themselves with PKCE, not
# a secret, and may only be sent back to the redirect URIs they registered.
class OauthClient < ApplicationRecord
  MAX_REDIRECT_URIS = 10

  has_many :api_tokens, dependent: :delete_all
  has_many :oauth_codes, dependent: :delete_all

  before_validation { self.client_id ||= "rapm_client_#{SecureRandom.base58(24)}" }
  validates :name, presence: true, length: { maximum: 200 }
  validate :redirect_uris_are_safe

  def redirect_uri?(uri) = redirect_uris.include?(uri)

  # https anywhere; plain http only back to this machine (native apps and
  # Claude Code listen on a loopback port).
  def self.safe_redirect_uri?(uri)
    parsed = URI.parse(uri)
    return false unless parsed.host.present? && parsed.fragment.nil?
    parsed.scheme == "https" || (parsed.scheme == "http" && %w[localhost 127.0.0.1 [::1]].include?(parsed.host))
  rescue URI::InvalidURIError
    false
  end

  private

  def redirect_uris_are_safe
    if redirect_uris.blank? || redirect_uris.size > MAX_REDIRECT_URIS
      errors.add(:redirect_uris, "must list 1 to #{MAX_REDIRECT_URIS} URIs")
    elsif (bad = redirect_uris.reject { |u| self.class.safe_redirect_uri?(u) }).any?
      errors.add(:redirect_uris, "must be https (or http on localhost): #{bad.first.to_s.truncate(100)}")
    end
  end
end
