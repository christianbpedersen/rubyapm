class AppsController < ApplicationController
  before_action :load_app, only: %i[show settings regenerate_key destroy]
  # Members watch apps; adding, deleting and the ingest keys are for admins.
  before_action :require_admin, only: %i[new create settings regenerate_key destroy]

  def index
    @apps = App.order(:name)
    @summaries = @apps.to_h do |app|
      m = Metrics.new(app, range: "1h")
      [app.id, { web: m.summary(m.app_scope(type: "web")), jobs: m.summary(m.app_scope(type: "job")),
                 series: m.timeseries(m.app_scope(type: "web")), metrics: m }]
    end
  end

  def show
    @type = params[:type] == "job" ? "job" : "web"
    scope = metrics.app_scope(type: @type)
    @summary = metrics.summary(scope)
    @series = metrics.timeseries(scope)
    @job_series = metrics.timeseries(metrics.app_scope(type: "job")) if @type == "web"
    @percentiles = metrics.percentile_series(scope)
    @histogram = metrics.histogram_chart(scope)
    @transactions = metrics.transactions(type: @type, limit: 10)
    @sql = metrics.sql_statements(tx_type: @type, limit: 8)
    @external = metrics.external_hosts.first(6)
    @traces = metrics.traces(tx_type: @type, limit: 8)
    @errors = metrics.error_groups(tx_type: @type).first(5)
  end

  def new
    @app = App.new
  end

  def create
    @app = App.new(params.require(:app).permit(:name, :apdex_t))
    if @app.save
      redirect_to settings_app_path(@app), notice: "Created #{@app.name}. Install the agent with the key below."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def settings; end

  def regenerate_key
    current_app.regenerate_api_key!
    redirect_to settings_app_path(current_app), notice: "New API key generated. Update the agent's configuration; the old key stops working now."
  end

  def destroy
    unless params[:confirm_name] == current_app.name
      return redirect_to(settings_app_path(current_app), alert: "Type the app name exactly to delete it.")
    end

    name = current_app.name
    current_app.destroy_with_data!
    redirect_to apps_path, notice: "Deleted #{name} and all of its data."
  end
end
