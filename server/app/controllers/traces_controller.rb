class TracesController < ApplicationController
  before_action :load_app

  def show
    @trace = Trace.where(app_id: current_app.id).find(params[:id])
    @rows = []
    flatten(@trace.tree, 0, nil)
    @total = @trace.duration.to_f.nonzero? || 1.0
    @sql_keys = @rows.filter_map { |r| r[:attrs]&.dig("key") }
    @sql_counts = @sql_keys.tally
  end

  private

  # Tree nodes are [name, category, start_ms, duration_ms, children, attrs?].
  def flatten(node, depth, parent_id)
    return unless node.is_a?(Array) && node.size >= 5

    id = @rows.size
    children = node[4] || []
    child_time = children.sum { |c| c[3].to_f }
    @rows << { id: id, parent: parent_id, depth: depth, name: node[0], category: node[1], start: node[2].to_f,
               duration: node[3].to_f, exclusive: [node[3].to_f - child_time, 0].max, attrs: node[5], children: children.size }
    children.each { |c| flatten(c, depth + 1, id) }
  end
end
