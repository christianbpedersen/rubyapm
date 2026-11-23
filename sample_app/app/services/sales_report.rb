# Analytics over the large, unindexed page_views table: the sample's
# source of slow, sequentially scanned queries with real EXPLAIN plans.
class SalesReport
  include RubyAPM::MethodTracer

  def views_by_country(path_prefix = "/products")
    PageView.where("path LIKE ?", "#{path_prefix}%").group(:country).order(Arel.sql("count(*) DESC")).limit(10).count
  end

  def top_products(country)
    PageView.where(country: country).group(:product_id).order(Arel.sql("count(*) DESC")).limit(10).count
  end

  def slow_referrers
    PageView.where("duration_ms > ?", 5_000).group(:referrer).average(:duration_ms)
  end

  def revenue_by_category
    LineItem.joins(product: :category).group("categories.name").sum("line_items.price_cents * line_items.quantity")
  end

  trace_method :views_by_country, :top_products, :slow_referrers, :revenue_by_category
end
