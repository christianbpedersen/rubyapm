# Before/after view of a deployment: the same window length either side of
# the deploy (cut short by neighbouring deploys and by "now").
class DeployComparison
  Side = Struct.new(:metrics, :summary, :transactions, :from, :to)

  attr_reader :deployment, :before, :after, :minutes

  def initialize(deployment, minutes: 30, type: "web")
    @deployment = deployment
    @type = type
    at = deployment.deployed_at
    # Old deploys only have hourly data; compare whole hours either side.
    @coarse = at < Compactor.horizon
    unit = @coarse ? 1.hour : 1.minute
    @minutes = @coarse ? (minutes / 60.0).ceil.clamp(1, 4) * 60 : minutes
    prev_deploy = Deployment.where(app_id: deployment.app_id).where(deployed_at: ...at).maximum(:deployed_at)
    next_deploy = Deployment.where(app_id: deployment.app_id).where("deployed_at > ?", at).minimum(:deployed_at)
    # Half-open, unit-aligned windows; the unit containing the deploy belongs
    # to neither side, since it mixes old and new code.
    before_to = floor(at, unit)
    after_from = floor(at, unit) + unit
    before_from = [before_to - @minutes.minutes, prev_deploy && (floor(prev_deploy, unit) + unit)].compact.max
    live_end = floor(Time.current - Metrics::INGEST_LAG.seconds, 1.minute)
    after_to = [after_from + @minutes.minutes, next_deploy && floor(next_deploy, unit), live_end].compact.min
    @before = side(before_from, before_to)
    @after = side(after_from, after_to)
  end

  def coarse? = @coarse

  # Alert incidents overlapping either window: likely confounders when the
  # numbers move for reasons other than the deploy.
  def overlapping_incidents
    Incident.includes(:alert_policy).where(app_id: @deployment.app_id)
            .where("opened_at < ? AND (closed_at IS NULL OR closed_at > ?)", @after.to, @before.from)
            .order(:opened_at)
  end

  def ready?
    @after.summary[:count].positive? && @before.summary[:count].positive?
  end

  # Per transaction: avg and p95 before/after, sorted by the absolute change
  # in time consumed per minute (the change that matters most to users).
  def transaction_changes(limit: 30)
    before = @before.transactions.index_by { |t| t[:name] }
    after = @after.transactions.index_by { |t| t[:name] }
    (before.keys | after.keys).filter_map do |name|
      b = before[name]
      a = after[name]
      next unless a && b && a[:count] >= 5 && b[:count] >= 5
      {
        name: name, type: a[:type], before: b, after: a,
        avg_change: change(b[:avg], a[:avg]), p95_change: change(b[:p95], a[:p95]),
        error_change: a[:error_rate] - b[:error_rate],
        impact: (a[:avg] - b[:avg]) * a[:rpm] # extra ms of work per minute at current traffic
      }
    end.sort_by { |c| -c[:impact].abs }.first(limit)
  end

  def change(before, after)
    return nil if before.nil? || after.nil? || before.zero?
    (after - before) / before
  end

  private

  def floor(time, unit)
    Time.at((time.to_i / unit.to_i) * unit.to_i).utc
  end

  def side(from, to)
    to = from + 1.minute if to <= from
    m = Metrics.new(@deployment.app, from: from.to_i, to: to.to_i, exact: true)
    Side.new(m, m.summary(m.app_scope(type: @type)), m.transactions(type: @type, limit: 200), from, to)
  end
end
