module Sources
  # Batches belongs_to lookups: one query per model per tick instead of N.
  class RecordSource < GraphQL::Dataloader::Source
    def initialize(model)
      @model = model
    end

    def fetch(ids)
      records = @model.where(id: ids).index_by(&:id)
      ids.map { |id| records[id] }
    end
  end

  class ReviewsByProduct < GraphQL::Dataloader::Source
    def fetch(product_ids)
      grouped = Review.where(product_id: product_ids).order(id: :desc).group_by(&:product_id)
      product_ids.map { |id| (grouped[id] || []).first(5) }
    end
  end
end
