module Api
  class InventoryController < ApplicationController
    def sync
      ids = Array.new(5) { rand(1..2000) }
      InventorySyncJob.perform_later(ids)
      head :accepted
    end
  end
end
