class AlertsController < ApplicationController
  before_action :load_app
  before_action :load_policy, only: %i[edit update destroy]

  def index
    @policies = current_app.alert_policies.order(:name)
    @open = current_app.incidents.open.includes(:alert_policy).order(opened_at: :desc)
    @incidents = current_app.incidents.includes(:alert_policy).order(opened_at: :desc).limit(50)
    @highlight = params[:incident].to_i
  end

  def new
    @policy = current_app.alert_policies.new(metric: params[:metric] || "p95", tx_name: params[:tx_name], tx_type: params[:tx_type] || "web")
    @policy.comparison, @policy.threshold = AlertPolicy::METRICS.dig(@policy.metric, :default) || ["above", 1000]
    @policy.name = [@policy.metric_label, @policy.tx_name].compact.join(" · ")
  end

  def create
    @policy = current_app.alert_policies.new(policy_params)
    if @policy.save
      redirect_to app_alerts_path(current_app), notice: "Alert “#{@policy.name}” created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @policy.update(policy_params)
      redirect_to app_alerts_path(current_app), notice: "Alert “#{@policy.name}” saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @policy.destroy
    redirect_to app_alerts_path(current_app), notice: "Alert “#{@policy.name}” deleted."
  end

  private

  def load_policy
    @policy = current_app.alert_policies.find(params[:id])
  end

  def policy_params
    params.require(:alert_policy).permit(:name, :metric, :tx_type, :tx_name, :target, :comparison, :threshold,
                                         :window_minutes, :min_samples, :webhook_url, :enabled)
          .tap { |p| p[:tx_name] = p[:tx_name].presence; p[:target] = p[:target].presence }
  end
end
