class GraphqlController < ApplicationController
  before_action :load_app

  def index
    @operations = metrics.transactions(query: "GraphQL/").select { |t| t[:name].start_with?("GraphQL/") }
                         .sort_by { |t| -t[:total] }
    @fields = metrics.segments(categories: %w[graphql], limit: 300)
    @resolvers = @fields.select { |f| f[:name].start_with?("GraphQL/field/") }
    callers = metrics.distinct_callers(metrics.segment_scope, :name, @resolvers.first(40).map { |f| f[:name] })
    @resolvers.each { |f| f[:callers] = callers[f[:name]] }
    @sources = @fields.select { |f| f[:name].start_with?("GraphQL/Source/") }
    @phases = @fields.select { |f| f[:name].match?(%r{\AGraphQL/(lex|parse|validate|analyze|execute)\z}) }
    scope = metrics.tx_scope.where("name LIKE 'GraphQL/%'")
    @summary = metrics.summary(scope)
    @series = metrics.timeseries(scope)
    @op_series = metrics.tx_series_by_name(nil, @operations.first(6).map { |o| o[:name] }, metric: :rpm)
    @field_series = metrics.stacked_segments(@resolvers.first(6).map { |f| f[:name] }, metric: :excl)
  end
end
