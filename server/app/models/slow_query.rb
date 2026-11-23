class SlowQuery < ApplicationRecord
  belongs_to :app
  belongs_to :statement, class_name: "SqlStatement", primary_key: :key, foreign_key: :key, optional: true
end
