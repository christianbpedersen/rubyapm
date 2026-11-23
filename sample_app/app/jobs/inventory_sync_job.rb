class InventorySyncJob < ApplicationJob
  queue_as :default

  def perform(product_ids)
    Product.where(id: product_ids).find_each do |product|
      stock = ExternalApi.get("inventory", "/stock/#{product.sku}")["stock"]
      product.update_columns(stock: stock, updated_at: Time.current)
    end
  end
end
