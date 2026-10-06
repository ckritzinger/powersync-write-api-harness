import { reactive, watch } from 'vue';
import type { CrudTransaction } from '@powersync/web';

export interface TestUser {
  id: string;
  name: string;
  role: string;
}

export interface HarnessConfig {
  writeApiUrl: string;
  powersyncUrl: string;
  backendUrl: string;
  users: TestUser[];
}

export type FatalPolicy = 'retain' | 'complete';

export interface Settings {
  userId: string;
  /** Default answer of onFatalTransaction for client-directed failures. */
  fatalPolicy: FatalPolicy;
  maxTransactions: number;
  maxOperations: number;
}

export interface LogEntry {
  id: number;
  at: string;
  kind: 'retry' | 'transport-error' | 'fatal-hook' | 'info';
  summary: string;
  detail?: unknown;
}

/** A client-directed fatal transaction seen by onFatalTransaction. */
export interface ClientFatal {
  transactionId: number;
  hookCalls: number;
  firstSeen: string;
  lastSeen: string;
  lastDecision: 'retain' | 'complete' | null;
  /** Set by the UI; the next hook call for this transaction answers 'complete'. */
  releaseRequested: boolean;
  released: boolean;
  errorCode: string;
  message?: string;
  details?: unknown;
  operationIndex?: number;
  crud: { op: string; table: string; id: string; opData?: Record<string, unknown> }[];
}

const SETTINGS_KEY = 'harness-settings';

const defaults: Settings = {
  userId: '',
  fatalPolicy: 'retain',
  maxTransactions: 1,
  maxOperations: 1000
};

function loadSettings(): Settings {
  try {
    return { ...defaults, ...JSON.parse(localStorage.getItem(SETTINGS_KEY) ?? '{}') };
  } catch {
    return { ...defaults };
  }
}

export const settings = reactive<Settings>(loadSettings());
watch(settings, (value) => localStorage.setItem(SETTINGS_KEY, JSON.stringify(value)), { deep: true });

export const harness = reactive({
  config: null as HarnessConfig | null,
  log: [] as LogEntry[],
  clientFatals: [] as ClientFatal[]
});

let logId = 0;
export function log(kind: LogEntry['kind'], summary: string, detail?: unknown) {
  harness.log.unshift({ id: ++logId, at: new Date().toISOString(), kind, summary, detail });
  if (harness.log.length > 300) harness.log.length = 300;
}

export function trackClientFatal(
  transaction: CrudTransaction,
  failed: { error_code: string; message?: string; details?: unknown; operation_index?: number },
  message?: string
): ClientFatal {
  const now = new Date().toISOString();
  let entry = harness.clientFatals.find((f) => f.transactionId === transaction.transactionId && !f.released);
  if (!entry) {
    entry = reactive<ClientFatal>({
      transactionId: transaction.transactionId ?? -1,
      hookCalls: 0,
      firstSeen: now,
      lastSeen: now,
      lastDecision: null,
      releaseRequested: false,
      released: false,
      errorCode: failed.error_code,
      crud: transaction.crud.map((c) => ({ op: c.op, table: c.table, id: c.id, opData: c.opData }))
    });
    harness.clientFatals.unshift(entry);
  }
  entry.hookCalls += 1;
  entry.lastSeen = now;
  entry.errorCode = failed.error_code;
  entry.message = failed.message ?? message;
  entry.details = failed.details;
  entry.operationIndex = failed.operation_index;
  return entry;
}
