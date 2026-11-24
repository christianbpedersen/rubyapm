# Someone who can sign in to the dashboard. Admins also manage users.
# Accounts start without a password: an admin hands out a setup link and the
# person picks their own password there (the same link resets a password).
class User < ApplicationRecord
  ROLES = %w[admin member].freeze
  MIN_PASSWORD = 12

  has_secure_password validations: false
  has_many :sessions, dependent: :delete_all
  has_many :api_tokens, dependent: :delete_all

  normalizes :email, with: ->(e) { e.strip.downcase }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validate :email_is_unique
  validates :role, inclusion: { in: ROLES }
  validates :password, length: { minimum: MIN_PASSWORD, maximum: 72 }, confirmation: true, allow_nil: true

  # Changing the password (or setting the first one) invalidates the link.
  generates_token_for :password_setup, expires_in: 3.days do
    password_digest.to_s
  end

  scope :admins, -> { where(role: "admin") }

  def admin? = role == "admin"
  def activated? = password_digest.present?
  def display_name = name.presence || email

  # The last admin can neither be removed nor demoted, so someone can
  # always manage users.
  def last_admin?
    admin? && User.admins.where.not(id: id).none?
  end

  def self.authenticate(email, password)
    user = find_by(email: email.to_s.strip.downcase)
    unless user&.activated?
      BCrypt::Password.create(password.to_s) # same cost as a real check, so timing reveals no accounts
      return nil
    end
    user.authenticate(password) || nil
  end

  private

  def email_is_unique
    return if email.blank?
    errors.add(:email, "is already taken") if User.where.not(id: id).exists?(["lower(email) = ?", email.downcase])
  end
end
