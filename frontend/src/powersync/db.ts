import { ref, type Ref } from 'vue';
import { PowerSyncDatabase } from '@powersync/web';
import { AppSchema } from './schema';
import { HarnessConnector } from './connector';
import { USER_ID_STORAGE_KEY } from '../example-client/library/powersync/DemoConnectorConfig';
import { log } from '../state';

export interface Session {
  db: PowerSyncDatabase;
  connector: HarnessConnector;
  /**
   * Whether connect() is in effect. Not the same as sync status: while the SDK retries a failing
   * sync connection it reports neither connected nor connecting, yet keeps uploading queued writes.
   */
  active: Ref<boolean>;
}

/**
 * One local database per test user, so switching identity never uploads one user's queued
 * writes with another user's token. Switching users reloads the page.
 */
export function openSession(userId: string): Session {
  // The reference connector takes its identity from this key and asks the token endpoint for it.
  localStorage.setItem(USER_ID_STORAGE_KEY, userId);
  const db = new PowerSyncDatabase({
    schema: AppSchema,
    database: { dbFilename: `harness-${userId}.sqlite` }
  });
  return { db, connector: new HarnessConnector(), active: ref(false) };
}

export async function connect({ db, connector, active }: Session) {
  log('info', 'Connecting to PowerSync');
  active.value = true;
  await db.connect(connector, { retryDelayMs: 3000 });
}

export async function disconnect({ db, active }: Session) {
  await db.disconnect();
  active.value = false;
  log('info', 'Disconnected; writes stay queued locally');
}

/**
 * Uploads without a PowerSync connection, through the same connector. Only allowed while
 * disconnected so it never races the SDK's own upload loop. Useful for testing the write API
 * against a DB the PowerSync instance does not replicate, and for building up multi-transaction
 * queues before a single batched flush.
 */
export async function flushOnce({ db, connector, active }: Session) {
  if (active.value) throw new Error('Disconnect first; the SDK is uploading.');
  log('info', 'Manual upload (one uploadData call)');
  try {
    await connector.uploadData(db);
  } catch (error) {
    log('info', `uploadData threw (transaction retained): ${error instanceof Error ? error.message : String(error)}`);
  }
}
