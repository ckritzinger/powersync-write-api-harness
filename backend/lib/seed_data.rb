require "time"

# Seed rows for lists/todos, written directly to the source database by `rake harness:seed`
# (provisioning, like migrations; the app itself never writes). Owners are the test users
# (app/services/test_users.rb). IDs are fixed so seeding is idempotent and rows are easy to
# recognise: lists 5eed0000-…-0000000000NN, todos 5eed0000-…-00000000NNMM.
module SeedData
  OWNERS = TestUsers.ids.freeze
  BASE = Time.utc(2026, 1, 5, 9, 0, 0)

  def self.list_id(n) = format("5eed0000-0000-4000-8000-%012d", n)
  def self.todo_id(list, n) = format("5eed0000-0000-4000-9000-%08d%04d", list, n)

  # [list number, owner, name, [[title, completed, position, minutes after list creation, edited minutes later or nil]]]
  LISTS = [
    [1, "user-alice", "Groceries", [
      ["Milk", true, 1, 5, 120],
      ["Eggs", false, 2, 6, nil],
      ["Sourdough bread", false, 3, 7, nil],
      ["Coffee beans (dark roast)", true, 4, 8, 200],
      ["Tomatoes", false, 5, 9, nil],
      ["Olive oil", false, 6, 10, 15]
    ]],
    [2, "user-alice", "Work — Q3 launch", [
      ["Draft release notes", true, 1, 1, 60],
      ["Review PR #482", false, 1.5, 2, 30], # mid-point position, as after a drag-reorder
      ["Update API docs", false, 2, 3, nil],
      ["Book launch retro", false, 3, 4, nil],
      ["Fix flaky test in CI", true, 4, 5, 300],
      ["Title with \"quotes\", commas, and an apostrophe's", false, 5, 6, nil],
      ["Unicode: café, naïve, 日本語, emoji 🚀", false, 6, 7, nil],
      ["A deliberately long title to check wrapping in both the client list view and the read oracle table — " \
       "it keeps going past any reasonable width so truncation and layout issues show up early", false, 7, 8, nil]
    ]],
    [3, "user-alice", "Empty list", []],
    [4, "user-bob", "Home repairs", [
      ["Fix leaking kitchen tap", false, 1, 10, nil],
      ["Replace hallway bulb", true, 2, 11, 45],
      ["Paint the fence", false, 3, 12, nil],
      ["Clean gutters", false, -1, 13, 5] # negative position: dragged above the first item
    ]],
    [5, "user-bob", "Weekend", [
      ["Hike", true, 1, 20, 90],
      ["Farmers market", true, 2, 21, 95],
      ["Call parents", false, 3, 22, nil]
    ]],
    [6, "user-carol", "Reading list", [
      ["The Pragmatic Programmer", true, 1, 30, 600],
      ["Designing Data-Intensive Applications", false, 2, 31, nil],
      ["Crafting Interpreters", false, 3, 32, nil],
      ["Release It!", false, 4, 33, nil]
    ]]
  ].freeze

  # Plain hashes, engine-neutral. Times are UTC with millisecond precision.
  def self.lists
    LISTS.map do |n, owner, name, _todos|
      { "id" => list_id(n), "owner_id" => owner, "name" => name, "created_at" => BASE + n * 3600 }
    end
  end

  def self.todos
    LISTS.flat_map do |n, _owner, _name, items|
      created_list = BASE + n * 3600
      items.each_with_index.map do |(title, completed, position, created_after, edited_after), i|
        # Distinct whole milliseconds, so every engine stores identical values.
        created = (created_list + created_after * 60 + Rational(i * 137, 1000)).round(3)
        {
          "id" => todo_id(n, i + 1),
          "list_id" => list_id(n),
          "title" => title,
          "completed" => completed,
          "position" => position.to_f,
          "created_at" => created,
          "updated_at" => edited_after ? created + edited_after * 60 : created
        }
      end
    end
  end
end
