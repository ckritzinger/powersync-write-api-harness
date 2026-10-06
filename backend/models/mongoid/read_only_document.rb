# Shared by the Mongoid models: the oracle never writes, every write goes through the write API.
module ReadOnlyDocument
  extend ActiveSupport::Concern

  included do
    include Mongoid::Document
    # Documents use the client's UUID string as _id (see write API mongo persister).
    field :_id, type: String
  end

  def readonly?
    true
  end
end
