class SearchController < ApplicationController
  def index
    q = params[:q].to_s
    # ILIKE on an unindexed text column: a sequential scan every time.
    @products = Product.includes(:category).where("name ILIKE ? OR description ILIKE ?", "%#{q}%", "%#{q}%").limit(30)
  end
end
