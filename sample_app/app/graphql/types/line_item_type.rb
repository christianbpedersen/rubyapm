module Types
  class LineItemType < BaseObject
    field :quantity, Integer, null: false
    field :product, Types::ProductType, null: false
    def product = dataloader.with(Sources::RecordSource, Product).load(object.product_id)
  end
end
