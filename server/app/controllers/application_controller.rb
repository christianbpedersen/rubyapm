class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  helper_method :metrics, :range_params, :current_app

  # Every dashboard page needs a signed-in user (see Authentication). The
  # agent ingest API and the MCP endpoint have their own controllers and
  # authenticate by API key and bearer token.
  include Authentication

  private

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
