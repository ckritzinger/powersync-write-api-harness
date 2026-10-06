<script setup lang="ts">
import { ref } from 'vue';
import { settings } from '../state';
import { otherUser, useSession } from '../session';
import {
  createListForOtherOwner,
  createMixedTransaction,
  createSentinelTodo,
  createTodoWithBadListId,
  createTodoWithNullTitle,
  queueSequence,
  type SequenceStep
} from '../data';

const props = defineProps<{ listId: string | null }>();
const { db } = useSession();

const sequence = ref('ok, bad-list, ok');
const STEPS: SequenceStep[] = ['ok', 'bad-list', 'null-title', 'sentinel', 'foreign-owner'];

async function act(action: () => Promise<unknown>, needsList = false) {
  if (needsList && !props.listId) return alert('Select a list first.');
  try {
    await action();
  } catch (error) {
    alert(error instanceof Error ? error.message : String(error));
  }
}

const mixedTransaction = () => act(() => createMixedTransaction(db, settings.userId));

function runSequence() {
  const steps = sequence.value.split(',').map((s) => s.trim()) as SequenceStep[];
  const unknown = steps.filter((s) => !STEPS.includes(s));
  if (unknown.length) return alert(`Unknown steps: ${unknown.join(', ')}. Use: ${STEPS.join(', ')}`);
  return act(
    () => queueSequence(db, steps, { listId: props.listId!, ownerId: settings.userId, otherOwnerId: otherUser()!.id }),
    steps.some((s) => s === 'ok' || s === 'null-title' || s === 'sentinel')
  );
}
</script>

<template>
  <div class="debug">
    <h2>Upload settings</h2>
    <label class="field">
      onFatalTransaction
      <select v-model="settings.fatalPolicy">
        <option value="retain">retain (release by hand in Client fatals)</option>
        <option value="complete">complete automatically</option>
      </select>
    </label>
    <label class="field">
      Max transactions / request
      <input v-model.number="settings.maxTransactions" type="number" min="1" max="50" />
    </label>
    <label class="field">
      Max operations / request
      <input v-model.number="settings.maxOperations" type="number" min="1" />
    </label>

    <h2>Debug writes</h2>
    <div class="actions">
      <button @click="act(() => createTodoWithBadListId(db))">
        Todo with bad list_id
        <small>FK violation → backend-directed fatal (no FK on MongoDB)</small>
      </button>
      <button @click="act(() => createSentinelTodo(db, listId!), true)">
        Todo titled __TRIGGER_CONFIRMATION__
        <small>needs sentinel override → client-directed fatal</small>
      </button>
      <button @click="act(() => createTodoWithNullTitle(db, listId!), true)">
        Todo with null title
        <small>NOT NULL / $jsonSchema violation</small>
      </button>
      <button @click="act(() => createListForOtherOwner(db, otherUser()!.id))">
        List owned by {{ otherUser()?.id }}
        <small>custom authorizer deny case (UNAUTHORIZED)</small>
      </button>
      <button @click="mixedTransaction">
        Mixed transaction
        <small>1 list PUT + 3 todo PUTs + 1 PATCH in one tx</small>
      </button>
    </div>

    <h2>Queue a sequence</h2>
    <p class="muted">
      One transaction per step: {{ STEPS.join(', ') }}. Disconnect, queue, set max transactions ≥ steps, then
      "Upload once" to see stop/skip and not_attempted in one response.
    </p>
    <div class="row">
      <input v-model="sequence" class="grow mono" />
      <button class="primary" @click="runSequence">Queue</button>
    </div>
  </div>
</template>

<style scoped>
.debug h2 {
  margin-top: 16px;
}
.debug h2:first-child {
  margin-top: 0;
}
.field {
  display: grid;
  grid-template-columns: 170px 1fr;
  gap: 4px 8px;
  align-items: center;
  margin-bottom: 6px;
}
.field .muted {
  grid-column: 2;
  font-size: 12px;
}
.actions {
  display: grid;
  gap: 6px;
}
.actions button {
  text-align: left;
  display: flex;
  flex-direction: column;
}
.actions small {
  color: var(--muted);
}
.grow {
  flex: 1;
}
</style>
