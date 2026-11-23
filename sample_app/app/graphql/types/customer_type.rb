module Types
  class CustomerType < BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :country, String
    field :orders, [Types::OrderType], null: false

    # Not batched: each customer's orders load separately (an N+1 the
    # GraphQL page makes visible per field).
    def orders = object.orders.order(id: :desc).limit(5)
  end
end
