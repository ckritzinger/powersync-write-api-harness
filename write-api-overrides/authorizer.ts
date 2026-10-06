// Harness override for powersync-reference-write-implementation/backend/src/auth/authorizer.ts.
// Copy over that file (imports are relative to backend/src/auth/). Behavior is chosen at
// request time from environment variables, so one build covers every TestPlan §3/§6 case:
//
//   HARNESS_AUTHZ=allow       (default) allow every authenticated write, like the stock authorizer
//   HARNESS_AUTHZ=owner       deny viewers (role claim) and any `lists` write whose owner_id is not auth.sub
//   HARNESS_AUTHZ=deny        deny everything (UNAUTHORIZED on every transaction)
//
//   HARNESS_SENTINEL=on       (default) a todo titled __TRIGGER_CONFIRMATION__ throws
//                             FatalOperationError('USER_CONFIRMATION_REQUIRED') — pair with the
//                             fatal-error-handler override to route it to the client.
//   HARNESS_SENTINEL=off      sentinel titles are ordinary data
//
// Values are read on each call; restart is only needed if your env loading requires it.

import type { CrudEntry } from '../types.js';
import type { AuthContext } from './types.js';
import { FatalOperationError } from '../errors.js';

export interface Authorizer {
  authorize(crud: CrudEntry[], auth: AuthContext): boolean | Promise<boolean>;
}

export const CONFIRMATION_SENTINEL = '__TRIGGER_CONFIRMATION__';

function checkSentinel(crud: CrudEntry[]) {
  if ((process.env.HARNESS_SENTINEL ?? 'on') === 'off') return;
  for (const [index, entry] of crud.entries()) {
    if (entry.table === 'todos' && entry.op !== 'DELETE' && entry.op_data?.title === CONFIRMATION_SENTINEL) {
      throw new FatalOperationError(
        'USER_CONFIRMATION_REQUIRED',
        'Confirm the change before retrying.',
        { record_id: entry.id, table: entry.table, reason: 'sentinel title' },
        index
      );
    }
  }
}

function ownerPolicy(crud: CrudEntry[], auth: AuthContext): boolean {
  if (auth.claims.role === 'viewer') {
    console.warn(`[harness authz] deny: ${auth.sub} has role viewer`);
    return false;
  }
  // Checks only the submitted owner_id; see docs/authorization.md for why real ownership checks
  // belong in the persister. Enough to exercise the per-row deny path.
  const foreign = crud.find(
    (entry) =>
      entry.table === 'lists' &&
      entry.op !== 'DELETE' &&
      entry.op_data?.owner_id !== undefined &&
      entry.op_data.owner_id !== auth.sub
  );
  if (foreign) {
    console.warn(`[harness authz] deny: ${auth.sub} wrote list ${foreign.id} owned by ${String(foreign.op_data?.owner_id)}`);
    return false;
  }
  return true;
}

export const authorizer: Authorizer = {
  async authorize(crud, auth) {
    checkSentinel(crud);

    const mode = process.env.HARNESS_AUTHZ ?? 'allow';
    if (mode === 'deny') {
      console.warn(`[harness authz] deny-all mode: rejecting transaction from ${auth.sub}`);
      return false;
    }
    if (mode === 'owner') return ownerPolicy(crud, auth);
    return true;
  }
};
