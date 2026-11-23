class DatabaseController < ApplicationController
  before_action :load_app

  SORTS = { "total" => :total, "avg" => :avg, "count" => :count, "max" => :max, "max_per_tx" => :max_per_tx }.freeze

  def index
    @sort = SORTS.key?(params[:sort]) ? params[:sort] : "total"
    scope = metrics.app_scope
    @summary = metrics.summary(scope)
    @series = metrics.timeseries(scope)
    @by_table = metrics.sql_by_table
    @statements = metrics.sql_statements(table: params[:table], operation: params[:op], query: params[:q], limit: 200)
                         .sort_by { |s| -s[SORTS[@sort]].to_f }
    @db_segments = metrics.segments(categories: %w[database activerecord], limit: 12)
    @segment_series = metrics.stacked_segments(@db_segments.first(6).map { |s| s[:name] }, metric: :excl)
    @n_plus_one = @statements.select { |s| s[:n_plus_one] }.sort_by { |s| -s[:max_per_tx] }.first(10)
    callers = metrics.distinct_callers(metrics.sql_scope, :key, @n_plus_one.map { |s| s[:key] })
    @n_plus_one.each { |s| s[:callers] = callers[s[:key]].to_i }
  end

  def show
    @statement = SqlStatement.find_by!(app_id: current_app.id, key: params[:key])
    @stats = metrics.sql_statements(key: @statement.key, limit: 1).first || {}
    @series = metrics.sql_timeseries(@statement.key)
    @percentiles = metrics.sql_percentile_series(@statement.key)
    @histogram = metrics.sql_histogram_chart(@statement.key)
    @overall = metrics.sql_percentiles(@statement.key)
    @callers = metrics.sql_callers(@statement.key)
    @samples = SlowQuery.where(app_id: current_app.id, key: @statement.key, ts: metrics.from..metrics.to).order(duration: :desc).limit(20)
    @plan = PlanAnalyzer.new(@samples.find { |s| s.explain.present? }&.explain || @statement.last_explain)
  end
end
