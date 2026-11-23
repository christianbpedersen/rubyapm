# Computes order totals: discounts, tax and a shipping quote from the
# shipping API. Traced per method so it shows up under "Code & classes".
class PricingService
  include RubyAPM::MethodTracer

  TAX = { "US" => 0.07, "DK" => 0.25, "DE" => 0.19, "GB" => 0.2 }.freeze

  def initialize(customer, items)
    @customer = customer
    @items = items
  end

  def quote
    subtotal = @items.sum { |product, qty| product.price_cents * qty }
    discount = loyalty_discount(subtotal)
    tax = tax_for(subtotal - discount)
    shipping = shipping_quote
    { subtotal: subtotal, discount: discount, tax: tax, shipping: shipping, total: subtotal - discount + tax + shipping }
  end

  def loyalty_discount(subtotal)
    past = @customer.orders.where(status: "paid").count
    past > 3 ? (subtotal * 0.05).round : 0
  end

  def tax_for(amount)
    # A little honest CPU work.
    rate = TAX.fetch(@customer.country, 0.1)
    5_000.times.reduce(0) { |acc, i| acc + (i % 7) }
    (amount * rate).round
  end

  def shipping_quote
    ExternalApi.post("shipping", "/rates", country: @customer.country, items: @items.size)["cents"]
  end

  trace_method :quote, :loyalty_discount, :tax_for, :shipping_quote
end
