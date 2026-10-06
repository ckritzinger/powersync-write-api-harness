<script setup lang="ts">
import { harness } from '../state';

// Connector hook activity only. The uploads themselves go straight from the browser to the write
// API: see the browser's Network tab for the requests and responses.
const kindClass: Record<string, string> = { 'transport-error': 'bad', 'fatal-hook': 'warn', retry: 'warn' };
</script>

<template>
  <div>
    <div class="row">
      <button @click="harness.log = []">Clear</button>
      <span class="muted">Newest first. Request/response bodies: browser Network tab (POST /api/data to the write API).</span>
    </div>
    <div v-for="entry in harness.log" :key="entry.id" class="entry">
      <div class="row">
        <span class="mono muted">{{ entry.at.slice(11, 23) }}</span>
        <span class="badge" :class="kindClass[entry.kind]">{{ entry.kind }}</span>
        <span>{{ entry.summary }}</span>
      </div>
      <details v-if="entry.detail !== undefined">
        <summary>detail</summary>
        <pre>{{ JSON.stringify(entry.detail, null, 2) }}</pre>
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
