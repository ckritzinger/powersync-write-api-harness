<script setup lang="ts">
import { harness, log, type ClientFatal } from '../state';

function release(entry: ClientFatal) {
  entry.releaseRequested = true;
  log('info', `Release requested for tx ${entry.transactionId}; applies on the next upload retry`);
}

function clearReleased() {
  harness.clientFatals = harness.clientFatals.filter((f) => !f.released);
}
</script>

<template>
  <div>
    <p class="muted">
      Client-directed fatal transactions seen by <span class="mono">onFatalTransaction</span>. A retained transaction
      blocks every later upload; the hook runs again on each retry (call count). "Release" makes the next call return
      <span class="mono">'complete'</span>, which discards the write locally — it does not mean it was applied.
    </p>
    <div class="row">
      <button :disabled="!harness.clientFatals.some((f) => f.released)" @click="clearReleased">Clear released</button>
    </div>
    <p v-if="!harness.clientFatals.length" class="muted">None yet.</p>
    <div v-for="entry in harness.clientFatals" :key="`${entry.transactionId}-${entry.firstSeen}`" class="fatal">
      <div class="row">
        <strong>tx {{ entry.transactionId }}</strong>
        <span class="badge bad">{{ entry.errorCode }}</span>
        <span v-if="entry.released" class="badge ok">released</span>
        <span v-else-if="entry.releaseRequested" class="badge warn">release pending</span>
        <span v-else class="badge warn">retained</span>
        <span class="muted">hook calls: {{ entry.hookCalls }}</span>
        <button v-if="!entry.released && !entry.releaseRequested" class="primary" @click="release(entry)">
          Release ('complete')
        </button>
      </div>
      <div class="muted">{{ entry.message }}</div>
      <div class="muted mono">
        first {{ entry.firstSeen }} · last {{ entry.lastSeen }}
        <template v-if="entry.operationIndex !== undefined"> · operation_index {{ entry.operationIndex }}</template>
      </div>
      <details>
        <summary>details &amp; operations</summary>
        <pre>{{ JSON.stringify({ details: entry.details, crud: entry.crud }, null, 2) }}</pre>
      </details>
    </div>
  </div>
</template>

<style scoped>
.fatal {
  border-top: 1px solid var(--border);
  padding: 8px 0;
}
</style>
