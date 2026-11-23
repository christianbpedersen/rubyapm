class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  helper_method :metrics, :range_params, :current_app

  # Dashboard sign-in: the shared chirpbin.com login when AUTH_INTERNAL_URL is
  # set, otherwise optional HTTP Basic auth (RUBY_APM_DASHBOARD_PASSWORD).
  # The agent ingest API has its own controller and authenticates by API key.
  before_action :require_chirpbin_login, if: -> { ChirpbinAuth.enabled? }
  before_action :authenticate_dashboard, unless: -> { ChirpbinAuth.enabled? }

  rescue_from ChirpbinAuth::Unavailable do |e|
    Rails.logger.error("[auth] #{e.message}")
    render plain: "Sign-in is temporarily unavailable. Please try again in a moment.", status: :service_unavailable
  end


  private

  def require_chirpbin_login
    @current_user = ChirpbinAuth.current_user(cookies[ChirpbinAuth::COOKIE])
    if @current_user == ChirpbinAuth::FORBIDDEN
      render plain: "You're signed in, but your account hasn't been given access to APM. " \
                    "Ask an admin to grant it at #{ChirpbinAuth.public_url}/admin/users.", status: :forbidden
    elsif @current_user.nil?
      redirect_to ChirpbinAuth.login_url(return_to: request.original_url), allow_other_host: true
    end
  end

  def authenticate_dashboard
    password = ENV["RUBY_APM_DASHBOARD_PASSWORD"].presence
    return unless password

    user = ENV.fetch("RUBY_APM_DASHBOARD_USER", "admin")
    authenticate_or_request_with_http_basic("RubyAPM") do |u, p|
      ActiveSupport::SecurityUtils.secure_compare(u, user) & ActiveSupport::SecurityUtils.secure_compare(p, password)
    end
  end

  def current_app
    @current_app
  end

  def load_app
    @current_app = App.find(params[:app_id] || params[:id])
  end

  # The time window rides along on every link so drill-downs keep context.
  def range_params
    if params[:from].present? && params[:to].present?
      { from: params[:from], to: params[:to] }
    else
      { range: Metrics::RANGES.key?(params[:range]) ? params[:range] : "1h" }
    end
  end

  def metrics
    @metrics ||= Metrics.new(current_app, range: params[:range], from: params[:from], to: params[:to])
  end
end
