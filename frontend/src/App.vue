<script setup lang="ts">
import { ref } from 'vue';
import { useStatus } from '@powersync/vue';
import { harness, settings } from './state';
import { useSession } from './session';
import { connect, disconnect, flushOnce } from './powersync/db';
import ListsPane from './components/ListsPane.vue';
import TodosPane from './components/TodosPane.vue';
import DebugPanel from './components/DebugPanel.vue';
import FatalPanel from './components/FatalPanel.vue';
import QueuePanel from './components/QueuePanel.vue';
import LogPanel from './components/LogPanel.vue';
import DeadLetterPanel from './components/DeadLetterPanel.vue';

const session = useSession();
const status = useStatus();
const selectedListId = ref<string | null>(null);
const tab = ref<'debug' | 'fatals' | 'queue' | 'log' | 'dead'>('debug');
const busy = ref(false);

function switchUser(event: Event) {
  settings.userId = (event.target as HTMLSelectElement).value;
  // One local DB per user: reload to open the other user's database and connector.
  location.reload();
}

async function run(action: () => Promise<void>) {
  busy.value = true;
  try {
    await action();
  } catch (error) {
    alert(error instanceof Error ? error.message : String(error));
  } finally {
    busy.value = false;
  }
}

const unreleasedFatals = () => harness.clientFatals.filter((f) => !f.released).length;
</script>

<template>
  <header class="topbar">
    <strong>Write API Harness</strong>
    <label class="row">
      User
      <select :value="settings.userId" @change="switchUser">
        <option v-for="u in harness.config?.users" :key="u.id" :value="u.id">{{ u.name }} — {{ u.id }}</option>
      </select>
    </label>
    <span class="badge" :class="status.connected ? 'ok' : status.connecting ? 'warn' : 'bad'">
      sync:
      {{ status.connected ? 'connected' : status.connecting ? 'connecting' : session.active.value ? 'retrying' : 'disconnected' }}
    </span>
    <span v-if="status.dataFlowStatus.uploading" class="badge warn">uploading</span>
    <span v-if="status.dataFlowStatus.uploadError" class="badge bad" :title="String(status.dataFlowStatus.uploadError)">
      upload error
    </span>
    <span v-if="status.dataFlowStatus.downloadError" class="badge bad" :title="String(status.dataFlowStatus.downloadError)">
      download error
    </span>
    <span class="spacer" />
    <button v-if="session.active.value" :disabled="busy" @click="run(() => disconnect(session))">
      Disconnect (queue offline)
    </button>
    <template v-else>
      <button :disabled="busy" title="One uploadData() call through the same connector" @click="run(() => flushOnce(session))">
        Upload once (manual)
      </button>
      <button class="primary" :disabled="busy" @click="run(() => connect(session))">Connect</button>
    </template>
  </header>

  <div class="endpoints muted mono">
    write API {{ harness.config?.writeApiUrl }} (direct) · PowerSync {{ harness.config?.powersyncUrl }} · tokens
    {{ harness.config?.backendUrl }}
  </div>

  <main class="layout">
    <ListsPane v-model:selected="selectedListId" />
    <TodosPane :list-id="selectedListId" />
    <section class="panel side">
      <nav class="tabs">
        <button :class="{ active: tab === 'debug' }" @click="tab = 'debug'">Debug</button>
        <button :class="{ active: tab === 'fatals' }" @click="tab = 'fatals'">
          Client fatals <span v-if="unreleasedFatals()" class="badge bad">{{ unreleasedFatals() }}</span>
        </button>
        <button :class="{ active: tab === 'queue' }" @click="tab = 'queue'">Queue</button>
        <button :class="{ active: tab === 'log' }" @click="tab = 'log'">Upload log</button>
        <button :class="{ active: tab === 'dead' }" @click="tab = 'dead'">Dead letters</button>
      </nav>
      <DebugPanel v-if="tab === 'debug'" :list-id="selectedListId" />
      <FatalPanel v-else-if="tab === 'fatals'" />
      <QueuePanel v-else-if="tab === 'queue'" />
      <LogPanel v-else-if="tab === 'log'" />
      <DeadLetterPanel v-else />
    </section>
  </main>
</template>

<style scoped>
.topbar {
  display: flex;
  gap: 12px;
  align-items: center;
  flex-wrap: wrap;
  padding: 10px 16px;
  background: var(--panel);
  border-bottom: 1px solid var(--border);
}
.spacer {
  flex: 1;
}
.endpoints {
  padding: 6px 16px;
  font-size: 11px;
}
.layout {
  display: grid;
  grid-template-columns: minmax(220px, 1fr) minmax(320px, 2fr) minmax(380px, 2fr);
  gap: 12px;
  padding: 0 16px 16px;
  align-items: start;
}
@media (max-width: 1100px) {
  .layout {
    grid-template-columns: 1fr;
  }
}
.tabs {
  display: flex;
  gap: 4px;
  flex-wrap: wrap;
  margin-bottom: 12px;
}
.tabs button.active {
  border-color: var(--accent);
  color: var(--accent);
}
</style>
