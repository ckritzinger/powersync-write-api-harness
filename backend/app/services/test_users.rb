# The hardcoded test identities. The single source for: token subjects (TokenIssuer), the
# frontend's user switcher (GET /api/users), and the seed data owners (lib/seed_data.rb).
# `id` becomes the JWT `sub`, which PowerSync sync streams (auth.user_id()) and the write API's
# AuthContext see. `role` is an extra claim for custom authorizer experiments
# (write-api-overrides/authorizer.ts).
module TestUsers
  User = Struct.new(:id, :name, :role, keyword_init: true)

  ALL = [
    User.new(id: "user-alice", name: "Alice (editor)", role: "editor"),
    User.new(id: "user-bob", name: "Bob (editor)", role: "editor"),
    User.new(id: "user-carol", name: "Carol (viewer — denied by custom authorizer)", role: "viewer")
  ].freeze

  def self.ids = ALL.map(&:id)
  def self.find(id) = ALL.find { |user| user.id == id }
end
