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

export const AppSchema = new Schema({ lists, todos });

export type Database = (typeof AppSchema)['types'];
export type ListRecord = Database['lists'];
export type TodoRecord = Database['todos'];
