import { column, Schema, Table } from '@powersync/web';

// Must match the source DB tables (backend/db/migrate) and sync streams (powersync/) exactly:
// the write API's default mapper preserves table and column names as-is.

const lists = new Table({
  owner_id: column.text,
  name: column.text,
  created_at: column.text
});

const todos = new Table(
  {
    list_id: column.text,
    title: column.text,
    completed: column.integer,
    position: column.real,
    created_at: column.text,
    updated_at: column.text
  },
  { indexes: { list: ['list_id'] } }
);

// Deliberately NOT a source table. The sync stream serves it as `SELECT *, title AS fake_title FROM todos
// AS expanded_todos`, so a naive mapper that writes `expanded_todos` / `fake_title` straight through hits a
// missing table and a missing column. Same columns as todos plus fake_title.
const expanded_todos = new Table(
  {
    list_id: column.text,
    title: column.text,
    fake_title: column.text,
    completed: column.integer,
    position: column.real,
    created_at: column.text,
    updated_at: column.text
  },
  { indexes: { list: ['list_id'] } }
);

export const AppSchema = new Schema({ lists, todos, expanded_todos });

export type Database = (typeof AppSchema)['types'];
export type ListRecord = Database['lists'];
export type TodoRecord = Database['todos'];
export type ExpandedTodoRecord = Database['expanded_todos'];
