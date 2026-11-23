module Types
  class ProductType < BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :price_cents, Integer, null: false
    field :stock, Integer, null: false
    field :category, Types::CategoryType, null: false
    field :reviews, [Types::ReviewType], null: false
    field :average_rating, Float, trace: true
    field :live_stock, Integer, description: "Stock from the inventory service"
    field :recommendations, [Types::ProductType], null: false

    def category = dataloader.with(Sources::RecordSource, Category).load(object.category_id)
    def reviews = dataloader.with(Sources::ReviewsByProduct).load(object.id)
    def average_rating = object.average_rating
    def live_stock = ExternalApi.get("inventory", "/stock/#{object.sku}")["stock"]
    def recommendations = RecommendationEngine.new(object).recommendations(3)
  end
end
