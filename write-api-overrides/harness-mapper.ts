// Optional write API mapper for the harness's `expanded_todos` test (see CLAUDE.md). Not part of the harness
// build: it is copied into the write API checkout, whose Docker build cannot follow a symlink out of its context.
//
// Install (from this repo's root), then `docker compose up --build` in the write API repo:
//
//   W=../powersync-reference-write-implementation/backend/src
//   cp write-api-overrides/harness-mapper.ts $W/mapping/harness.ts
//
// and in $W/persistence/persister-factories.ts:
//
//   import { harnessMapper } from '../mapping/harness.js';
//   ...
//   mysql: (uri) => createMySQLPersister(uri, harnessMapper),
//
// Remove after the test: delete $W/mapping/harness.ts and `git checkout` persister-factories.ts in the write API.
// Without it the default mapper writes `expanded_todos` straight through and fails with SCHEMA_MISMATCH.
// Postgres and SQL Server factories would need the same one-line change; MongoDB uses its own mapper.

import type { EntryMapper } from './types.js';

// Client table -> source table, and per-table client column -> source column.
const TABLES: Record<string, { table: string; columns: Record<string, string> }> = {
  expanded_todos: { table: 'todos', columns: { fake_title: 'title' } }
};

/**
 * Same pass-through as defaultMapper (no value conversion or validation), plus the renames above.
 * Not built on defaultMapper because that logs an error on every call.
 */
export const harnessMapper: EntryMapper = (entry) => {
  const rule = TABLES[entry.table];
  const table = rule?.table ?? entry.table;

  const raw = entry.op_data ?? {};
  const id = (entry.id ?? raw.id) as string;

  if (entry.op === 'DELETE') {
    return { table, op: entry.op, id, data: {} };
  }

  const { id: _discardId, ...fields } = raw;
  if (!rule) return { table, op: entry.op, id, data: fields };

  const data: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(fields)) {
    const target = rule.columns[key] ?? key;
    // The stream serves title and fake_title as the same value. If a PUT carries both, the renamed
    // column must not overwrite the real one with a stale copy: the real source column wins.
    if (target !== key && target in fields) continue;
    data[target] = value;
  }
  return { table, op: entry.op, id, data };
};
