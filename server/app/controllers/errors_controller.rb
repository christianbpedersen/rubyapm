class ErrorsController < ApplicationController
  before_action :load_app

  def index
    @groups = metrics.error_groups
    @series = metrics.error_series
    @summary = metrics.summary(metrics.app_scope)
  end

  def show
    @group = ErrorGroup.find_by!(app_id: current_app.id, fingerprint: params[:fingerprint])
    @series = metrics.error_series(fingerprint: @group.fingerprint)
    @by_tx = ErrorRollup.where(app_id: current_app.id, fingerprint: @group.fingerprint, ts: metrics.from..metrics.to)
                        .group(:tx_type, :tx_name).order(Arel.sql("sum(count) DESC")).pluck(:tx_type, :tx_name, Arel.sql("sum(count)"))
    @traces = Trace.where(app_id: current_app.id, error_class: @group.error_class, tx_name: @by_tx.map { |r| r[1] })
                   .where(ts: metrics.from..metrics.to).order(ts: :desc).limit(10)
  end
end
