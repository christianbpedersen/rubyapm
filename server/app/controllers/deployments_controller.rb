class DeploymentsController < ApplicationController
  before_action :load_app

  def index
    @deployments = Deployment.where(app_id: current_app.id).order(deployed_at: :desc).limit(50)
    @comparisons = @deployments.first(10).to_h { |d| [d.id, DeployComparison.new(d)] }
  end

  def show
    @deployment = Deployment.where(app_id: current_app.id).find(params[:id])
    @minutes = params[:minutes].present? ? params[:minutes].to_i.clamp(5, 240) : 30
    @cmp = DeployComparison.new(@deployment, minutes: @minutes)
    @minutes = @cmp.minutes
    @changes = @cmp.transaction_changes
    @zoom = { from: (@deployment.deployed_at - @minutes.minutes).to_i, to: (@deployment.deployed_at + @minutes.minutes).to_i }
    @zoom_metrics = Metrics.new(current_app, **@zoom)
    @series = @zoom_metrics.timeseries(@zoom_metrics.app_scope(type: "web"))
    @percentiles = @zoom_metrics.percentile_series(@zoom_metrics.app_scope(type: "web"))
  end
end
