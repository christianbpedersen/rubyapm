# Reads an EXPLAIN plan (PostgreSQL text format, with basic MySQL/SQLite
# support) and points out the usual suspects behind a slow query.
class PlanAnalyzer
  Finding = Struct.new(:severity, :title, :detail)
  Node = Struct.new(:depth, :text, :cost, :rows)

  SEQ_SCAN_ROWS = 1_000
  BIG_ROWS = 100_000

  attr_reader :plan, :findings, :nodes

  def initialize(plan)
    @plan = plan.to_s
    @findings = []
    @nodes = []
    analyze if present?
  end

  def present?
    @plan.present? && !failed?
  end

  # The agent sends "EXPLAIN failed: …" or "EXPLAIN skipped: …" instead of a plan.
  def failed?
    @plan.match?(/\AEXPLAIN (failed|skipped)/)
  end

  def total_cost
    @nodes.first&.cost
  end

  private

  def analyze
    lines = @plan.lines.map(&:rstrip).reject(&:blank?)
    lines.each do |line|
      indent = line[/\A\s*/].size
      text = line.strip.sub(/\A->\s*/, "")
      cost = line[/cost=[\d.]+\.\.([\d.]+)/, 1]&.to_f
      rows = line[/rows=(\d+)/, 1]&.to_i
      @nodes << Node.new(indent, text, cost, rows)
    end

    lines.each_with_index do |line, i|
      rows = line[/rows=(\d+)/, 1].to_i
      if (table = line[/Seq Scan on "?(\w+)"?/, 1])
        filter = lines[i + 1].to_s[/Filter: (.+)/, 1]
        cols = filter.to_s.scan(/\(?"?(\w+)"?\)?(?:::\w+)?\s*(?:=|<|>|<=|>=|~~|IS)/).flatten.uniq - %w[AND OR NOT]
        if rows >= SEQ_SCAN_ROWS || filter
          detail = "Postgres reads every row of #{table} (estimated #{rows.to_fs(:delimited)} rows)."
          detail += cols.any? ? " Consider an index on #{table}(#{cols.join(', ')})." : " Add a WHERE clause or an index that matches it."
          detail += " Filter: #{filter}" if filter
          @findings << Finding.new(rows >= BIG_ROWS ? :bad : :warn, "Sequential scan on #{table}", detail)
        end
      end
      if line =~ /Sort Method: external merge\s+Disk: (\d+)kB/
        @findings << Finding.new(:bad, "Sort spilled to disk", "The sort needed #{$1} kB on disk; raise work_mem or add an index matching ORDER BY.")
      elsif line.match?(/\A\s*(->\s*)?Sort\b/) && rows >= BIG_ROWS
        @findings << Finding.new(:warn, "Large sort", "Sorting ~#{rows.to_fs(:delimited)} rows; an index on the ORDER BY columns can avoid it.")
      end
      if line.match?(/Nested Loop/) && rows >= BIG_ROWS
        @findings << Finding.new(:warn, "Nested loop over many rows", "Estimated #{rows.to_fs(:delimited)} rows through a nested loop; check join keys are indexed.")
      end
      if line.match?(/Hash Join|Merge Join/) && rows >= BIG_ROWS * 10
        @findings << Finding.new(:info, "Very large join", "Join produces ~#{rows.to_fs(:delimited)} rows; consider narrowing it.")
      end
      if (t = line[/\bSCAN (?:TABLE )?(\w+)\z/, 1]) # SQLite
        @findings << Finding.new(:warn, "Full table scan on #{t}", "SQLite scans #{t} without an index.")
      end
      if line.include?("| ALL |") # MySQL type=ALL
        @findings << Finding.new(:warn, "Full table scan", "MySQL reports access type ALL; add an index for the WHERE clause.")
      end
    end

    if @findings.empty? && @plan.match?(/Index (Only )?Scan|Bitmap Index Scan|USING INDEX/)
      @findings << Finding.new(:info, "Uses an index", "The plan already uses an index; slowness is likely from row count, locking or load at that moment. Compare against the latency chart.")
    end
    @findings.uniq!(&:title)
  end
end
