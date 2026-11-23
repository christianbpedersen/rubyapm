class ProductsController < ApplicationController
  def index
    # Deliberate N+1: category and rating are loaded per product in the view.
    @products = Product.order(:id).offset((params[:page].to_i % 50) * 24).limit(24)
  end

  def show
    @product = Product.find(params[:id])
    @reviews = @product.reviews.includes(:customer).order(id: :desc).limit(20)
    @recommendations = RecommendationEngine.new(@product).recommendations
    @stock = ExternalApi.get("inventory", "/stock/#{@product.sku}")["stock"]
    PageView.create!(product_id: @product.id, path: request.path, referrer: "direct", country: "US", duration_ms: 0, viewed_at: Time.current)
  end
end
