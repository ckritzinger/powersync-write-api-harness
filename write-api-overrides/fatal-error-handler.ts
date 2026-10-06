// Harness override for powersync-reference-write-implementation/backend/src/fatal-error-handler.ts.
// Copy over that file (imports are relative to backend/src/). Keeps notifyDeadLetter and the
// exported types unchanged; only fatalErrorHandler differs. Environment variables, read per call:
//
//   HARNESS_DEAD_LETTER_URL   where onDeadLetter POSTs entries; the frontend's sink, e.g.
//                             http://localhost:5180/api/dead-letters (local backend) or
//                             http://host.docker.internal:5180/api/dead-letters (Docker Compose).
//                             Unset: log only.
//
//   HARNESS_CLASSIFY=default        USER_CONFIRMATION_REQUIRED → client, everything else → backend
//   HARNESS_CLASSIFY=backend        every fatal → backend (stock behavior)
//   HARNESS_CLASSIFY=client         every fatal → client
//   HARNESS_CLASSIFY=throw          requiresClientHandling throws → retryable, no dead letter
//   HARNESS_CLASSIFY=non-boolean    requiresClientHandling returns 'yes' → retryable, no dead letter
//
//   HARNESS_DEAD_LETTER=post        (default) POST to HARNESS_DEAD_LETTER_URL
//   HARNESS_DEAD_LETTER=throw       onDeadLetter throws synchronously → logged, response unaffected
//   HARNESS_DEAD_LETTER=reject      onDeadLetter rejects asynchronously → logged, response unaffected
//   HARNESS_DEAD_LETTER=hang        onDeadLetter never resolves → response unaffected
//   HARNESS_DEAD_LETTER=slow        POST after 10s → response unaffected

import { randomUUID } from 'node:crypto';
import type { AuthContext } from './auth/types.js';
import type { components } from './generated/api.js';
import type { FatalOperationError, JsonValue } from './errors.js';

export interface FatalErrorHandler {
  requiresClientHandling(error: FatalOperationError, context: FatalErrorContext): boolean | Promise<boolean>;
  onDeadLetter(entry: DeadLetterEntry): void | Promise<void>;
}

async function postDeadLetter(entry: DeadLetterEntry) {
  const url = process.env.HARNESS_DEAD_LETTER_URL;
  console.error('[harness dead-letter]', entry.errorCode, entry.message, `tx ${entry.transaction.transaction_id}`);
  if (!url) return;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(entry),
    signal: AbortSignal.timeout(5000)
  });
  if (!res.ok) throw new Error(`Dead-letter sink returned ${res.status}`);
}

export const fatalErrorHandler: FatalErrorHandler = {
  requiresClientHandling(error) {
    switch (process.env.HARNESS_CLASSIFY ?? 'default') {
      case 'backend':
        return false;
      case 'client':
        return true;
      case 'throw':
        throw new Error('[harness] requiresClientHandling deliberately threw');
      case 'non-boolean':
        return 'yes' as unknown as boolean;
      default:
        return error.errorCode === 'USER_CONFIRMATION_REQUIRED';
    }
  },
  onDeadLetter(entry) {
    switch (process.env.HARNESS_DEAD_LETTER ?? 'post') {
      case 'throw':
        throw new Error('[harness] onDeadLetter deliberately threw synchronously');
      case 'reject':
        return Promise.reject(new Error('[harness] onDeadLetter deliberately rejected'));
      case 'hang':
        return new Promise<void>(() => {});
      case 'slow':
        return new Promise<void>((resolve, reject) =>
          setTimeout(() => postDeadLetter(entry).then(resolve, reject), 10_000)
        );
      default:
        return postDeadLetter(entry);
    }
  }
};

// Unchanged from the reference implementation below.

export interface FatalErrorContext {
  transaction: components['schemas']['CrudTransaction'];
  auth: AuthContext;
}

export interface DeadLetterEntry {
  occurrenceId: string;
  timestamp: string;
  transaction: FatalErrorContext['transaction'];
  authenticatedSubject: string;
  errorCode: string;
  message: string;
  details?: JsonValue;
  operationIndex?: number;
}

/** Logs callback failures without changing the transaction result. Returned promises are not awaited. */
export function notifyDeadLetter(error: FatalOperationError, context: FatalErrorContext): void {
  try {
    const pending = fatalErrorHandler.onDeadLetter({
      occurrenceId: randomUUID(),
      timestamp: new Date().toISOString(),
      transaction: context.transaction,
      authenticatedSubject: context.auth.sub,
      errorCode: error.errorCode,
      message: error.message,
      details: error.details,
      operationIndex: error.operationIndex
    });
    void Promise.resolve(pending).catch((failure) => console.error('Dead-letter handler failed:', failure));
  } catch (failure) {
    console.error('Dead-letter handler failed:', failure);
  }
}
