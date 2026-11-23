class SearchController < ApplicationController
  before_action :load_app

  def index
    @q = params[:q].to_s.strip
    return if @q.empty?

    like = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
    since = metrics.from
    @transactions = TxRollup.where(app_id: current_app.id, ts: since..).where("name ILIKE ?", like)
                            .group(:tx_type, :name).order(Arel.sql("sum(total) DESC")).limit(25)
                            .pluck(:tx_type, :name, Arel.sql("sum(count), sum(total)"))
    @segments = SegmentRollup.where(app_id: current_app.id, ts: since..).where("name ILIKE ?", like)
                             .group(:name, :category).order(Arel.sql("sum(excl) DESC")).limit(25)
                             .pluck(:name, :category, Arel.sql("sum(count), sum(excl)"))
    @statements = SqlStatement.where(app_id: current_app.id).where("sql ILIKE ? OR table_name ILIKE ? OR location ILIKE ?", like, like, like)
                              .order(last_seen_at: :desc).limit(25)
    @errors = ErrorGroup.where(app_id: current_app.id).where("error_class ILIKE ? OR message ILIKE ?", like, like)
                        .order(last_seen_at: :desc).limit(25)
    if (exact = @transactions.find { |_, name, *| name.casecmp?(@q) })
      redirect_to app_transaction_path(current_app, type: exact[0], name: exact[1], **range_params)
    end
  end
end
