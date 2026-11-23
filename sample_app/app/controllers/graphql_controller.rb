class GraphqlController < ApplicationController
  def execute
    result = ShopSchema.execute(params[:query], variables: params[:variables]&.to_unsafe_h || {},
                                operation_name: params[:operationName], context: {})
    render json: result
  end
end
