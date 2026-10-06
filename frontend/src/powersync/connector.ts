// The connector under test is the reference modular connector, used through the
// src/example-client symlink (powersync-reference-write-implementation/example-client/src). This subclass overrides its
// protected hooks, plus ONE private method (see the constructor); everything else, including the
// upload loop, is the reference code.
//
// Uploads go straight from the browser to the write API: VITE_BACKEND_URL is the write API's URL
// (set by the frontend server from WRITE_API_URL), so POST /api/data is a cross-origin request and
// exercises the write API's CORS handling.
//
// Tokens come from the Rails app. The reference connector builds its token URL from the same
// VITE_BACKEND_URL, which would hit the write API's own demo token endpoint (keys PowerSync and the
// write API do not trust), so the constructor swaps in a token fetch against this app's origin, where
// the frontend server forwards /api/auth/token to Rails.

import type { CrudTransaction } from '@powersync/web';
import { PowersyncConnector } from '../example-client/PowersyncConnector';
import type { ClientHandledFatalResult, TransactionResult } from '../example-client/library/powersync/WriteAPIClient';
import type { BatchingConfig } from '../example-client/library/powersync/DemoConnectorConfig';
import { log, settings, trackClientFatal } from '../state';

export class HarnessConnector extends PowersyncConnector {
  constructor() {
    super();
    // `fetchAuthToken` is private in the reference connector, so TypeScript will not let a subclass
    // override it; at runtime an own property shadows the prototype method that getAuthToken() calls.
    // This is also how an app would swap in its identity provider's token retrieval.
    (this as unknown as { fetchAuthToken: () => Promise<string> }).fetchAuthToken = async () => {
      const res = await fetch(`/api/auth/token?user_id=${encodeURIComponent(this.userId)}`);
      if (!res.ok) throw new Error(`Token request failed (${res.status}): ${await res.text()}`);
      return (await res.json()).token;
    };
  }

  /** Batch limits come from the Debug tab instead of build-time VITE_BATCH_* variables. */
  protected getBatchingConfig(): BatchingConfig {
    const clamp = (n: number, min: number, max: number) => Math.min(max, Math.max(min, Math.floor(n) || min));
    return {
      maxTransactions: clamp(settings.maxTransactions, 1, 50),
      maxOperations: clamp(settings.maxOperations, 1, 100_000)
    };
  }

  /**
   * Client-directed fatal errors. The UI lists each retained transaction; "Release" there makes the
   * next call for it return 'complete'. The fatal policy setting can also complete automatically.
   */
  protected async onFatalTransaction(
    transaction: CrudTransaction,
    result: ClientHandledFatalResult
  ): Promise<'retain' | 'complete'> {
    const entry = trackClientFatal(transaction, result.failedOperation, result.message);
    const decision = entry.releaseRequested || settings.fatalPolicy === 'complete' ? 'complete' : 'retain';
    entry.lastDecision = decision;
    if (decision === 'complete') {
      entry.released = true;
      entry.releaseRequested = false;
    }
    log(
      'fatal-hook',
      `onFatalTransaction tx ${transaction.transactionId}: ${result.failedOperation.error_code} → ${decision} (call #${entry.hookCalls})`,
      result
    );
    return decision;
  }

  protected async onRetryableError(result: Extract<TransactionResult, { status: 'retryable_error' }>): Promise<never> {
    log('retry', `Retryable: ${result.message ?? '(no message)'}${result.retryAfterMs ? ` (retry after ${result.retryAfterMs}ms)` : ''}`);
    return super.onRetryableError(result);
  }

  protected async onTransportError(error: unknown): Promise<never> {
    log('transport-error', error instanceof Error ? error.message : String(error));
    return super.onTransportError(error);
  }
}
