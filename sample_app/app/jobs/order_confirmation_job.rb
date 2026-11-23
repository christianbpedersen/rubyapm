class OrderConfirmationJob < ApplicationJob
  queue_as :mailers

  def perform(order_id)
    order = Order.includes(:customer, line_items: :product).find(order_id)
    ExternalApi.post("email", "/send", to: order.customer.email, template: "order_confirmation", items: order.line_items.size)
    order.update!(status: "confirmed") if order.status == "paid"
  end
end
