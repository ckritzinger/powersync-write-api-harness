# Source tables for the write API under test. Names must match the PowerSync client schema
# (frontend/src/powersync/schema.ts) and sync streams exactly: the default mapper renames nothing.
#
# Same migration on every SQL engine. IDs are client-generated UUIDs: native uuid on Postgres,
# 36-char strings elsewhere (SQL Server's uniqueidentifier would sync back upper-cased).
class CreateListsAndTodos < ActiveRecord::Migration[8.0]
  def change
    create_table :lists, id: false do |t|
      id_column(t, :id, primary_key: true)
      t.string :owner_id, null: false
      t.string :name
      timestamp_column(t, :created_at)
    end
    add_index :lists, :owner_id

    create_table :todos, id: false do |t|
      id_column(t, :id, primary_key: true)
      id_column(t, :list_id, null: false)
      t.string :title, null: false
      t.boolean :completed, null: false, default: false
      t.float :position, limit: 53
      timestamp_column(t, :created_at)
      timestamp_column(t, :updated_at)
    end
    add_index :todos, :list_id
    # Natural failure for the "bad list_id" debug write; cascade keeps list deletes simple.
    add_foreign_key :todos, :lists, column: :list_id, on_delete: :cascade
  end

  private

  # Clients send ISO-8601 with a +00:00 offset. SQL Server's datetime2 does not parse offsets,
  # so it gets datetimeoffset; the other engines accept the offset into their plain datetime.
  def timestamp_column(t, name)
    if connection.adapter_name.match?(/sqlserver/i)
      t.column name, :datetimeoffset, precision: 3
    else
      t.datetime name, precision: 3
    end
  end

  def id_column(t, name, **options)
    if connection.adapter_name.match?(/postg/i)
      t.uuid name, **options
    else
      t.string name, limit: 36, **options
    end
  end
end
