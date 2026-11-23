class ReportsController < ApplicationController
  def sales
    report = SalesReport.new
    @by_country = report.views_by_country
    @top = report.top_products(%w[US DK DE GB FR].sample)
    @revenue = report.revenue_by_category
    @slow_referrers = report.slow_referrers if rand < 0.3
    ReportJob.perform_later(%w[US DK DE GB FR].sample) if rand < 0.2
  end

  # Cached most of the time; a cold cache falls through to the slow query.
  def live
    @counts = Rails.cache.fetch("reports/live/#{Time.current.to_i / 20}") { SalesReport.new.views_by_country("/search") }
    render json: @counts
  end
end
