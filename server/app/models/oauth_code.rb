# A single-use OAuth authorization code, bound to the client, the redirect
# URI and the PKCE challenge it was issued for. Lives ten minutes.
class OauthCode < ApplicationRecord
  TTL = 10.minutes

  belongs_to :user
  belongs_to :oauth_client

  attr_reader :code

  def self.issue!(**attrs)
    plaintext = "rapm_code_#{SecureRandom.base58(32)}"
    create!(code_digest: ApiToken.digest(plaintext), expires_at: TTL.from_now, **attrs).tap { |c| c.instance_variable_set(:@code, plaintext) }
  end

  # Marks the code used and returns it, or nil when it is unknown, expired,
  # already used, or does not match the client and PKCE verifier.
  def self.redeem(code, client:, redirect_uri:, verifier:)
    transaction do
      grant = lock.find_by(code_digest: ApiToken.digest(code), oauth_client_id: client.id)
      next nil unless grant && grant.used_at.nil? && grant.expires_at > Time.current
      next nil unless grant.redirect_uri == redirect_uri && grant.pkce_ok?(verifier)
      grant.update!(used_at: Time.current)
      grant
    end
  end

  # S256 only (RFC 7636): BASE64URL(SHA256(verifier)) == challenge.
  def pkce_ok?(verifier)
    return false unless verifier.to_s.match?(/\A[A-Za-z0-9\-._~]{43,128}\z/)
    expected = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    ActiveSupport::SecurityUtils.secure_compare(expected, code_challenge)
  end
end
