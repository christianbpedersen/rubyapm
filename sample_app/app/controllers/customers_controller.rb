class CustomersController < ApplicationController
  def history
    @customer = Customer.find(params[:id])
    # N+1 twice over: orders → line items → products.
    @orders = @customer.orders.order(id: :desc).limit(15)
  end
end
