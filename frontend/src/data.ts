import type { AbstractPowerSyncDatabase } from '@powersync/web';

// Every helper here is a local write; the SDK queues it and the connector uploads it.
// Transaction boundaries are deliberate: each exported function is one upload transaction.

/** Sentinel the write-API override (write-api-overrides/) turns into USER_CONFIRMATION_REQUIRED. */
export const CONFIRMATION_SENTINEL = '__TRIGGER_CONFIRMATION__';

export const uuid = () => crypto.randomUUID();
/**
 * ISO-8601 UTC with milliseconds and an explicit +00:00 offset. Not toISOString()'s trailing "Z":
 * MySQL rejects "Z" in DATETIME values, and the default mapper passes strings through unchanged.
 */
export const now = () => new Date().toISOString().replace('Z', '+00:00');

export async function createList(db: AbstractPowerSyncDatabase, ownerId: string, name: string) {
  const id = uuid();
  await db.execute('INSERT INTO lists (id, owner_id, name, created_at) VALUES (?, ?, ?, ?)', [id, ownerId, name, now()]);
  return id;
}

export async function renameList(db: AbstractPowerSyncDatabase, id: string, name: string) {
  await db.execute('UPDATE lists SET name = ? WHERE id = ?', [name, id]);
}

/** Deletes the todos then the list in one transaction (FK order). */
export async function deleteList(db: AbstractPowerSyncDatabase, id: string) {
  await db.writeTransaction(async (tx) => {
    await tx.execute('DELETE FROM todos WHERE list_id = ?', [id]);
    await tx.execute('DELETE FROM lists WHERE id = ?', [id]);
  });
}

async function nextPosition(db: AbstractPowerSyncDatabase, listId: string) {
  const row = await db.get<{ max: number | null }>('SELECT MAX(position) AS max FROM todos WHERE list_id = ?', [listId]);
  return (row.max ?? 0) + 1;
}

export async function createTodo(db: AbstractPowerSyncDatabase, listId: string, title: string | null) {
  const id = uuid();
  const ts = now();
  await db.execute(
    'INSERT INTO todos (id, list_id, title, completed, position, created_at, updated_at) VALUES (?, ?, ?, 0, ?, ?, ?)',
    [id, listId, title, await nextPosition(db, listId), ts, ts]
  );
  return id;
}

export async function updateTodoTitle(db: AbstractPowerSyncDatabase, id: string, title: string) {
  await db.execute('UPDATE todos SET title = ?, updated_at = ? WHERE id = ?', [title, now(), id]);
}

export async function setCompleted(db: AbstractPowerSyncDatabase, id: string, completed: boolean) {
  await db.execute('UPDATE todos SET completed = ?, updated_at = ? WHERE id = ?', [completed ? 1 : 0, now(), id]);
}

/** Drag-reorder: a single-column PATCH of `position` only (no updated_at), distinct from toggles. */
export async function setPosition(db: AbstractPowerSyncDatabase, id: string, position: number) {
  await db.execute('UPDATE todos SET position = ? WHERE id = ?', [position, id]);
}

export async function deleteTodo(db: AbstractPowerSyncDatabase, id: string) {
  await db.execute('DELETE FROM todos WHERE id = ?', [id]);
}

// Debug actions (TestPlan §3, §4, §6)

/** Natural DB failure: FK violation on SQL engines (no FK in MongoDB, so it succeeds there). */
export async function createTodoWithBadListId(db: AbstractPowerSyncDatabase) {
  const ts = now();
  await db.execute(
    'INSERT INTO todos (id, list_id, title, completed, position, created_at, updated_at) VALUES (?, ?, ?, 0, 1, ?, ?)',
    [uuid(), uuid(), 'orphan todo (bad list_id)', ts, ts]
  );
}

/** NOT NULL violation on SQL engines, $jsonSchema validation failure on MongoDB. */
export async function createTodoWithNullTitle(db: AbstractPowerSyncDatabase, listId: string) {
  await createTodo(db, listId, null);
}

/** Client-directed path: needs the sentinel override applied to the write API. */
export async function createSentinelTodo(db: AbstractPowerSyncDatabase, listId: string) {
  await createTodo(db, listId, CONFIRMATION_SENTINEL);
}

/** Per-row authz deny case: a list whose owner_id is not the authenticated subject. */
export async function createListForOtherOwner(db: AbstractPowerSyncDatabase, otherOwnerId: string) {
  return createList(db, otherOwnerId, `owned by ${otherOwnerId} (should be denied)`);
}

/** One transaction mixing tables and op types: PUT list, PUT todos, PATCH one todo. */
export async function createMixedTransaction(db: AbstractPowerSyncDatabase, ownerId: string) {
  await db.writeTransaction(async (tx) => {
    const listId = uuid();
    const ts = now();
    await tx.execute('INSERT INTO lists (id, owner_id, name, created_at) VALUES (?, ?, ?, ?)', [
      listId,
      ownerId,
      `mixed tx ${ts.slice(11, 19)}`,
      ts
    ]);
    const ids = [uuid(), uuid(), uuid()];
    for (const [i, id] of ids.entries()) {
      await tx.execute(
        'INSERT INTO todos (id, list_id, title, completed, position, created_at, updated_at) VALUES (?, ?, ?, 0, ?, ?, ?)',
        [id, listId, `item ${i + 1}`, i + 1, ts, ts]
      );
    }
    await tx.execute('UPDATE todos SET completed = 1 WHERE id = ?', [ids[0]]);
  });
}

export type SequenceStep = 'ok' | 'bad-list' | 'null-title' | 'sentinel' | 'foreign-owner';

/**
 * Queues one transaction per step, in order. Combine with a batch size >= steps and a manual
 * flush to watch stop/skip, not_attempted and client-directed stops within one request.
 */
export async function queueSequence(
  db: AbstractPowerSyncDatabase,
  steps: SequenceStep[],
  ctx: { listId: string; ownerId: string; otherOwnerId: string }
) {
  for (const [i, step] of steps.entries()) {
    if (step === 'ok') await createTodo(db, ctx.listId, `seq ${i + 1} ok`);
    if (step === 'bad-list') await createTodoWithBadListId(db);
    if (step === 'null-title') await createTodoWithNullTitle(db, ctx.listId);
    if (step === 'sentinel') await createSentinelTodo(db, ctx.listId);
    if (step === 'foreign-owner') await createListForOtherOwner(db, ctx.otherOwnerId);
  }
}
