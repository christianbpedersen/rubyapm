class OrdersController < ApplicationController
  def index
    @orders = Order.includes(:customer).order(id: :desc).limit(50)
  end

  def show
    @order = Order.includes(line_items: :product).find(params[:id])
  end

  # Checkout: price, charge the card, persist, enqueue confirmation.
  def create
    customer = Customer.find(params[:customer_id] || rand(1..5000))
    ids = Array(params[:product_ids]).presence || Array.new(rand(1..4)) { rand(1..2000) }
    items = Product.where(id: ids).map { |p| [p, rand(1..3)] }
    quote = PricingService.new(customer, items).quote
    charge = ExternalApi.post("payments", "/charges", amount: quote[:total], customer: customer.id)
    raise ExternalApi::PaymentDeclined, "card declined for customer #{customer.id}" if charge["status"] == "declined"

    order = Order.transaction do
      o = customer.orders.create!(status: "paid", total_cents: quote[:total], payment_ref: charge["id"])
      items.each { |p, qty| o.line_items.create!(product: p, quantity: qty, price_cents: p.price_cents) }
      Product.where(id: items.map { |p, _| p.id }).update_all("stock = GREATEST(stock - 1, 0)")
      o
    end
    render json: { id: order.id, total_cents: order.total_cents }, status: :created
  end
end
