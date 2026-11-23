module Types
  class ReviewType < BaseObject
    field :id, ID, null: false
    field :rating, Integer, null: false
    field :body, String
    field :customer, Types::CustomerType, null: false

    def customer = dataloader.with(Sources::RecordSource, Customer).load(object.customer_id)
  end
end
