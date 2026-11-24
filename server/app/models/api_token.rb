# Bearer tokens for the MCP endpoint: personal tokens a user creates for
# Claude Code or scripts, and the access/refresh tokens the OAuth server
# issues to clients such as claude.ai. Only a SHA-256 digest is stored; the
# token itself is shown once.
class ApiToken < ApplicationRecord
  KINDS = %w[personal access refresh].freeze
  PREFIX = { "personal" => "rapm_pat_", "access" => "rapm_at_", "refresh" => "rapm_rt_" }.freeze
  ACCESS_TTL = 1.hour
  REFRESH_TTL = 30.days

  belongs_to :user
  belongs_to :oauth_client, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :name, presence: true, if: -> { kind == "personal" }

  attr_reader :token

  scope :live, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :personal, -> { where(kind: "personal") }

  def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

  # Creates a token and keeps its plaintext on the instance (#token) for
  # this one response.
  def self.issue!(kind:, user:, **attrs)
    plaintext = PREFIX.fetch(kind) + SecureRandom.base58(40)
    create!(kind: kind, user: user, token_digest: digest(plaintext), **attrs).tap { |t| t.instance_variable_set(:@token, plaintext) }
  end

  # The token for an Authorization header, if it is live and may call the API.
  def self.authenticate(plaintext)
    return nil unless plaintext.to_s.start_with?(PREFIX["personal"], PREFIX["access"])

    token = live.where(kind: %w[personal access]).includes(:user).find_by(token_digest: digest(plaintext))
    return nil unless token
    token.update_column(:last_used_at, Time.current) if token.last_used_at.nil? || token.last_used_at < 1.minute.ago
    token
  end

  def expired? = expires_at.present? && expires_at <= Time.current
end
