class List < ApplicationRecord
  has_many :todos, -> { order(:position, :created_at, :id) }, inverse_of: :list

  scope :order_by_created, -> { order(:created_at, :id) }
end
