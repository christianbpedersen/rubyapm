class Order < ApplicationRecord
  belongs_to :customer
  has_many :line_items, dependent: :destroy
  has_many :products, through: :line_items

  after_commit :send_confirmation, on: :create

  private

  def send_confirmation
    OrderConfirmationJob.perform_later(id)
  end
end
