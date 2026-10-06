class Todo < ApplicationRecord
  belongs_to :list, optional: true

  scope :orphaned, -> { where.not(list_id: List.select(:id)) }
end
