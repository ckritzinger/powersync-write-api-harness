class Todo
  include ReadOnlyDocument
  store_in collection: "todos"

  field :list_id, type: String
  field :title, type: String
  field :completed, type: Mongoid::Boolean
  field :position, type: Float
  field :created_at, type: Time
  field :updated_at, type: Time

  # No foreign keys in MongoDB: a bad list_id is stored as-is, so this view matters here.
  def self.orphaned
    where(:list_id.nin => List.pluck(:_id))
  end

  def list
    List.where(_id: list_id).first
  end
end
