# Dashboard sign-in with RubyAPM's own users. A signed, http-only cookie
# holds the Session id; every page requires a signed-in user unless the
# controller opts out with allow_unauthenticated_access.
module Authentication
  extend ActiveSupport::Concern

  COOKIE = :rapm_session

  included do
    before_action :require_login
    helper_method :current_user, :signed_in?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_login, **options
    end
  end

  private

  def current_user = current_session&.user
  def signed_in? = current_user.present?

  def current_session
    return @current_session if defined?(@current_session)

    session_row = Session.includes(:user).find_by(id: cookies.signed[COOKIE])
    @current_session = session_row && !session_row.expired? ? session_row.tap(&:touch_seen!) : nil
  end

  def require_login
    return if signed_in?

    session[:return_to] = request.original_url if request.get? && !request.xhr?
    redirect_to login_path
  end

  def require_admin
    render plain: "Only admins can do that.", status: :forbidden unless current_user&.admin?
  end

  def start_session(user)
    reset_session # new Rails session id: no fixation across sign-in
    row = user.sessions.create!(ip_address: request.remote_ip, user_agent: request.user_agent.to_s.truncate(250), last_seen_at: Time.current)
    user.update_column(:last_sign_in_at, Time.current)
    cookies.signed.permanent[COOKIE] = { value: row.id, httponly: true, same_site: :lax, secure: request.ssl?, path: cookie_path }
    @current_session = row
  end

  def end_session
    current_session&.destroy
    cookies.delete(COOKIE, path: cookie_path)
    reset_session
    @current_session = nil
  end

  # Only ever back to this app, never to another host or path prefix.
  def after_login_url
    target = session.delete(:return_to).to_s
    home = "#{request.base_url}#{request.script_name}/"
    target.start_with?(home) ? target : root_url
  end

  # Scope the cookie to the mount point (/apm on chirpbin.com) so other apps
  # on the same host never see it.
  def cookie_path = request.script_name.presence || "/"
end
