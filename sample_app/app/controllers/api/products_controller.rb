module Api
  class ProductsController < ApplicationController
    def index
      render json: Product.order(:id).limit(50).pluck(:id, :name, :price_cents)
    end

    def show
      product = Product.find(params[:id])
      render json: product.slice(:id, :name, :price_cents, :stock)
    end
  end
end
