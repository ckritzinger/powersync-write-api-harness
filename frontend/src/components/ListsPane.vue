<script setup lang="ts">
import { ref } from 'vue';
import { useQuery } from '@powersync/vue';
import { settings } from '../state';
import { useSession } from '../session';
import { createList, deleteList, renameList } from '../data';
import type { ListRecord } from '../powersync/schema';

const selected = defineModel<string | null>('selected');
const { db } = useSession();

// Shows every local list, including rows with a foreign owner_id the write API has not (yet)
// rejected, so a denied local write stays visible until sync removes it.
const { data: lists } = useQuery<ListRecord & { id: string; todo_count: number }>(
  `SELECT lists.*, (SELECT COUNT(*) FROM todos WHERE todos.list_id = lists.id) AS todo_count
     FROM lists ORDER BY created_at, id`
);

const name = ref('');

async function add() {
  const id = await createList(db, settings.userId, name.value.trim() || `List ${new Date().toLocaleTimeString()}`);
  name.value = '';
  selected.value = id;
}

async function rename(list: ListRecord & { id: string }) {
  const next = prompt('List name', list.name ?? '');
  if (next !== null) await renameList(db, list.id, next);
}

async function remove(id: string) {
  if (selected.value === id) selected.value = null;
  await deleteList(db, id);
}
</script>

<template>
  <section class="panel">
    <h2>Lists</h2>
    <form class="row" @submit.prevent="add">
      <input v-model="name" placeholder="New list name" />
      <button class="primary" type="submit">Add</button>
    </form>
    <ul class="lists">
      <li v-for="list in lists" :key="list.id" :class="{ active: list.id === selected }" @click="selected = list.id">
        <div>
          <div>{{ list.name }}</div>
          <div class="muted mono">
            {{ list.todo_count }} todos
            <span v-if="list.owner_id !== settings.userId" class="badge warn">owner {{ list.owner_id }}</span>
          </div>
        </div>
        <span class="actions">
          <button @click.stop="rename(list)">Rename</button>
          <button class="danger" @click.stop="remove(list.id)">Delete</button>
        </span>
      </li>
      <li v-if="!lists.length" class="muted">No lists yet.</li>
    </ul>
  </section>
</template>

<style scoped>
.lists {
  list-style: none;
  padding: 0;
  margin: 12px 0 0;
}
.lists li {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
  padding: 8px;
  border-radius: 6px;
  cursor: pointer;
}
.lists li.active {
  background: #e8f0fd;
}
.actions {
  display: flex;
  gap: 4px;
}
</style>
