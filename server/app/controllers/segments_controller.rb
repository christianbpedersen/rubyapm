# "Code & classes": every instrumented unit of work across all transactions,
# from controller actions and custom-traced classes to views and AR models.
class SegmentsController < ApplicationController
  before_action :load_app

  CATEGORY_TABS = {
    "custom" => { label: "Custom classes", cats: %w[custom] },
    "controller" => { label: "Controllers", cats: %w[controller] },
    "view" => { label: "Views", cats: %w[view] },
    "activerecord" => { label: "ActiveRecord models", cats: %w[activerecord] },
    "job" => { label: "Jobs", cats: %w[job] },
    "cache" => { label: "Cache", cats: %w[cache] },
    "all" => { label: "Everything", cats: nil }
  }.freeze

  def index
    @tab = CATEGORY_TABS.key?(params[:cat]) ? params[:cat] : "custom"
    @segments = metrics.segments(categories: CATEGORY_TABS[@tab][:cats], query: params[:q], limit: 300)
    @segments = @segments.reject { |s| s[:name].start_with?("Middleware/") } unless @tab == "all"
    @grouped = group_by_class(@segments) if %w[custom activerecord].include?(@tab)
    @series = metrics.stacked_segments(@segments.first(8).map { |s| s[:name] }, metric: :excl)
  end

  def show
    @name = params.require(:name)
    @summary = metrics.segment_summary(@name)
    @series = metrics.segment_timeseries(@name)
    @callers = metrics.segment_callers(@name)
  end

  private

  # Custom/PricingService#quote and Custom/PricingService.for → PricingService.
  def group_by_class(segments)
    segments.group_by { |s| s[:name].split("/")[1].to_s.split(/[#.]/).first }.map do |klass, segs|
      { klass: klass, excl: segs.sum { |s| s[:excl] }, total: segs.sum { |s| s[:total] }, count: segs.sum { |s| s[:count] },
        methods: segs.size, share: segs.sum { |s| s[:share] } }
    end.sort_by { |g| -g[:excl] }
  end
end
