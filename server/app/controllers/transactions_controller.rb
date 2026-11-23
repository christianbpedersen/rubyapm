class TransactionsController < ApplicationController
  before_action :load_app

  SORTS = {
    "total" => ->(t) { -t[:total] }, "avg" => ->(t) { -t[:avg] }, "p95" => ->(t) { -(t[:p95] || 0) },
    "rpm" => ->(t) { -t[:rpm] }, "errors" => ->(t) { -t[:error_rate] }, "apdex" => ->(t) { t[:apdex] || 1 },
    "name" => ->(t) { t[:name] }
  }.freeze

  def index
    @type = params[:type] == "job" ? "job" : "web"
    @sort = SORTS.key?(params[:sort]) ? params[:sort] : "total"
    @transactions = metrics.transactions(type: @type, query: params[:q]).sort_by(&SORTS[@sort])
    scope = metrics.app_scope(type: @type)
    @series = metrics.timeseries(scope)
    top = @transactions.first(6).map { |t| t[:name] }
    @top_series = metrics.tx_series_by_name(@type, top)
  end

  def show
    @type = params[:type].presence || "web"
    @name = params.require(:name)
    scope = metrics.tx_scope(type: @type, name: @name)
    @summary = metrics.summary(scope)
    @series = metrics.timeseries(scope)
    @percentiles = metrics.percentile_series(scope)
    @histogram = metrics.histogram_chart(scope)
    @segments = metrics.segments(tx_type: @type, tx_name: @name)
    top_names = @segments.reject { |s| s[:name].start_with?("Middleware/") }.first(8).map { |s| s[:name] }
    @segment_series = metrics.segments_per_tx_series(top_names, tx_type: @type, tx_name: @name)
    @segment_meta = @segments.index_by { |s| s[:name] }
    @sql = metrics.sql_statements(tx_type: @type, tx_name: @name, limit: 50)
    @traces = metrics.traces(tx_type: @type, tx_name: @name, limit: 20)
    @errors = metrics.error_groups(tx_type: @type, tx_name: @name)
    @slow_queries = SlowQuery.where(app_id: current_app.id, tx_type: @type, tx_name: @name, ts: metrics.from..metrics.to)
                             .order(duration: :desc).limit(10)
    @statements = SqlStatement.where(app_id: current_app.id, key: @slow_queries.map(&:key)).index_by(&:key)
    @graphql = @name.start_with?("GraphQL/")
  end
end
