class ReportJob < ApplicationJob
  queue_as :reports

  def perform(country)
    report = SalesReport.new
    report.top_products(country)
    report.revenue_by_category
    Rails.cache.write("report/#{country}", report.views_by_country, expires_in: 5.minutes)
  end
end
