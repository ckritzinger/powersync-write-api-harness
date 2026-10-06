class List
  include ReadOnlyDocument
  store_in collection: "lists"

  field :owner_id, type: String
  field :name, type: String
  field :created_at, type: Time

  def self.order_by_created
    order_by(created_at: :asc, _id: :asc)
  end

  def todos
    Todo.where(list_id: id).order_by(position: :asc, created_at: :asc, _id: :asc)
  end
end
