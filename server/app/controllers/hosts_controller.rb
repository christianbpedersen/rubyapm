class HostsController < ApplicationController
  before_action :load_app

  def index
    @hosts = current_app.hosts.order(last_seen_at: :desc).limit(200)
    @runtime = metrics.runtime_series
  end
end
