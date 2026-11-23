class SlowQueriesController < ApplicationController
  before_action :load_app

  def index
    @statements = metrics.slow_statements
    @series = metrics.slow_query_series
    @samples = SlowQuery.where(app_id: current_app.id, ts: metrics.from..metrics.to).order(duration: :desc).limit(50)
    @sql = SqlStatement.where(app_id: current_app.id, key: (@samples.map(&:key) + @statements.map { |s| s[:key] }).uniq).index_by(&:key)
    @threshold = SlowQuery.where(app_id: current_app.id).minimum(:duration)
  end

  def show
    @sample = SlowQuery.where(app_id: current_app.id).find(params[:id])
    @statement = SqlStatement.find_by(app_id: current_app.id, key: @sample.key)
    @plan = PlanAnalyzer.new(@sample.explain.presence || @statement&.last_explain)
    @trace = Trace.where(app_id: current_app.id, tx_type: @sample.tx_type, tx_name: @sample.tx_name)
                  .where(ts: (@sample.ts - 10.seconds)..(@sample.ts + 10.seconds)).order(duration: :desc).first
  end
end
