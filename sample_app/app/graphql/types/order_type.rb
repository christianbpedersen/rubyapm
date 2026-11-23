module Types
  class OrderType < BaseObject
    field :id, ID, null: false
    field :status, String, null: false
    field :total_cents, Integer, null: false
    field :line_items, [Types::LineItemType], null: false
    def line_items = object.line_items
  end
end
