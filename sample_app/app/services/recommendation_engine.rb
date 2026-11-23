# "Customers who viewed this also viewed": scores products by co-occurrence.
# Mostly Ruby CPU time with a couple of queries, so it is a distinct
# block in the layer breakdown.
class RecommendationEngine
  include RubyAPM::MethodTracer

  def initialize(product)
    @product = product
  end

  def recommendations(limit = 4)
    candidates = Product.where(category_id: @product.category_id).where.not(id: @product.id).limit(60).to_a
    scored = candidates.map { |p| [p, score(p)] }
    scored.sort_by { |_, s| -s }.first(limit).map(&:first)
  end

  # SHOPWELL_REGRESSION=1 simulates a bad deploy: a "smarter" scoring model
  # that is far more expensive and runs a query per candidate (an N+1).
  REGRESSION = ENV["SHOPWELL_REGRESSION"] == "1"
  ROUNDS = REGRESSION ? 15_000 : 300

  def score(candidate)
    candidate.reviews.where(rating: 5).count if REGRESSION
    seed = (candidate.id * 7919 + @product.id) % 1000
    (1..ROUNDS).reduce(seed) { |acc, i| (acc * 31 + i) % 100_003 } / 100_003.0
  end

  trace_method :recommendations
end
