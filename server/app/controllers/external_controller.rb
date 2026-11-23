class ExternalController < ApplicationController
  before_action :load_app

  def index
    @hosts = metrics.external_hosts
    @summary = metrics.summary(metrics.app_scope)
    names = @hosts.first(8).flat_map { |h| h[:segments].map { |s| s[:name] } }
    @time_series = host_series(names, :total)
    @call_series = host_series(names, :calls)
    @avg_series = metrics.stacked_segments(names, metric: :avg)
  end

  def show
    @host = params[:service]
    @entry = metrics.external_hosts.find { |h| h[:host] == @host }
    names = @entry ? @entry[:segments].map { |s| s[:name] } : []
    @series = names.to_h { |n| [n, metrics.segment_timeseries(n)] }
    @callers = names.flat_map { |n| metrics.segment_callers(n).map { |c| c.merge(segment: n) } }.sort_by { |c| -c[:total] }
  end

  private

  # One series per host, summing its verbs.
  def host_series(names, metric)
    metrics.stacked_segments(names, metric: metric).group_by { |n, _| n.split("/")[1] }.transform_values do |list|
      list.map(&:last).transpose.map { |vals| vals.compact.sum.round(2) }
    end
  end
end
