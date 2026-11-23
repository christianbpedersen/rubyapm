module Types
  class MutationType < BaseObject
    field :create_review, Types::ReviewType do
      argument :product_id, ID, required: true
      argument :customer_id, ID, required: true
      argument :rating, Integer, required: true
      argument :body, String, required: false
    end

    def create_review(product_id:, customer_id:, rating:, body: nil)
      Review.create!(product_id: product_id, customer_id: customer_id, rating: rating.clamp(1, 5), body: body)
    end
  end
end
