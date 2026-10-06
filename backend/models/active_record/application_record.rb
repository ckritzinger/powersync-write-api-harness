class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # The oracle never writes: every write must go through the write API under test.
  def readonly?
    true
  end

end
