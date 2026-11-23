class Product < ApplicationRecord
  belongs_to :category
  has_many :reviews
  has_many :line_items

  def price = price_cents / 100.0

  def average_rating
    reviews.average(:rating)&.round(1)
  end
end
