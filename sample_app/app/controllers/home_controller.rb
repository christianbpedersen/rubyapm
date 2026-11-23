class HomeController < ApplicationController
  def index
    @featured = Rails.cache.fetch("home/featured", expires_in: 30.seconds) { Product.order(stock: :desc).limit(8).to_a }
    @categories = Category.order(:name).to_a
    @recent_reviews = Review.includes(:product, :customer).order(id: :desc).limit(10)
  end
end
