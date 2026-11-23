module Types
  class QueryType < BaseObject
    field :products, [Types::ProductType], null: false do
      argument :category_id, ID, required: false
      argument :limit, Integer, required: false, default_value: 20
    end
    field :product, Types::ProductType do
      argument :id, ID, required: true
    end
    field :customer, Types::CustomerType do
      argument :id, ID, required: true
    end
    field :top_customers, [Types::CustomerType], null: false

    def products(category_id: nil, limit: 20)
      scope = Product.order(:id).limit([limit, 100].min)
      category_id ? scope.where(category_id: category_id) : scope
    end

    def product(id:) = Product.find(id)
    def customer(id:) = Customer.find(id)
    def top_customers = Customer.joins(:orders).group("customers.id").order(Arel.sql("sum(orders.total_cents) DESC")).limit(10)
  end
end
