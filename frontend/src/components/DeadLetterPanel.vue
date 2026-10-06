<script setup lang="ts">
import { onMounted, onUnmounted, ref } from 'vue';

interface Received {
  receivedAt: string;
  entry: {
    occurrenceId?: string;
    errorCode?: string;
    message?: string;
    authenticatedSubject?: string;
    operationIndex?: number;
    transaction?: { transaction_id?: number };
  };
}

const items = ref<Received[]>([]);
let timer: ReturnType<typeof setInterval> | undefined;

async function refresh() {
  const res = await fetch('/api/dead-letters');
  if (res.ok) items.value = await res.json();
}

async function clear() {
  await fetch('/api/dead-letters', { method: 'DELETE' });
  await refresh();
}

onMounted(() => {
  void refresh();
  timer = setInterval(refresh, 2000);
});
onUnmounted(() => clearInterval(timer));

/** Count per client transaction id: duplicates are expected (no dedup guarantee). */
const countFor = (txId: number | undefined) => items.value.filter((i) => i.entry.transaction?.transaction_id === txId).length;
</script>

<template>
  <div>
    <p class="muted">
      Entries POSTed to this app's <span class="mono">/api/dead-letters</span> by a write API whose
      <span class="mono">onDeadLetter</span> handler is set up to do so. All users, in memory, newest first.
    </p>
    <div class="row"><button @click="clear">Clear</button></div>
    <p v-if="!items.length" class="muted">None received.</p>
    <div v-for="item in items" :key="item.entry.occurrenceId ?? item.receivedAt" class="entry">
      <div class="row">
        <span class="mono muted">{{ item.receivedAt.slice(11, 23) }}</span>
        <span class="badge bad">{{ item.entry.errorCode }}</span>
        <span class="mono">{{ item.entry.authenticatedSubject }}</span>
        <span class="mono">tx {{ item.entry.transaction?.transaction_id }}</span>
        <span v-if="countFor(item.entry.transaction?.transaction_id) > 1" class="badge warn">
          ×{{ countFor(item.entry.transaction?.transaction_id) }} for this tx
        </span>
      </div>
      <div class="muted">{{ item.entry.message }}</div>
      <details>
        <summary>entry</summary>
        <pre>{{ JSON.stringify(item.entry, null, 2) }}</pre>
      </details>
    </div>
  </div>
</template>

<style scoped>
.entry {
  border-top: 1px solid var(--border);
  padding: 6px 0;
}
</style>
