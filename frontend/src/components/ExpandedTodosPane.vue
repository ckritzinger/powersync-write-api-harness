<script setup lang="ts">
import { computed } from 'vue';
import { useQuery } from '@powersync/vue';
import { useSession } from '../session';
import { updateExpandedFakeTitle } from '../data';
import type { ExpandedTodoRecord } from '../powersync/schema';

type Expanded = ExpandedTodoRecord & { id: string };

const props = defineProps<{ listId: string | null }>();
const { db } = useSession();

const params = computed(() => [props.listId ?? '']);
const { data: rows } = useQuery<Expanded>(
  'SELECT * FROM expanded_todos WHERE list_id = ? ORDER BY position, created_at, id',
  params
);

async function edit(row: Expanded) {
  const next = prompt('fake_title', row.fake_title ?? '');
  if (next !== null) await updateExpandedFakeTitle(db, row.id, next);
}
</script>

<template>
  <section class="panel">
    <h2>Expanded todos</h2>
    <p class="muted">
      Synced as <span class="mono">todos AS expanded_todos</span> with <span class="mono">title AS fake_title</span>. Neither
      exists in the source database, so editing <span class="mono">fake_title</span> only uploads if the write API maps the
      table and the column.
    </p>
    <p v-if="!listId" class="muted">Select a list.</p>
    <ul v-else class="rows">
      <li v-for="row in rows" :key="row.id">
        <span class="title">
          {{ row.fake_title ?? '(null)' }}
          <span class="muted mono">title: {{ row.title ?? 'null' }}</span>
        </span>
        <button @click="edit(row)">Edit fake_title</button>
      </li>
      <li v-if="!rows.length" class="muted">No rows.</li>
    </ul>
  </section>
</template>

<style scoped>
.rows {
  list-style: none;
  padding: 0;
  margin: 12px 0 0;
}
.rows li {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px;
  border-bottom: 1px solid var(--border);
}
.title {
  flex: 1;
}
</style>
