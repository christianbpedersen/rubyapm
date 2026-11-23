class ShopSchema < GraphQL::Schema
  query Types::QueryType
  mutation Types::MutationType
  use GraphQL::Dataloader
  max_complexity 2_000
end
