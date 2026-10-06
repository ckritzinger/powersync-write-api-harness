<script setup lang="ts">
import { computed, ref } from 'vue';
import { useQuery } from '@powersync/vue';
import { useSession } from '../session';
import { createTodo, deleteTodo, setCompleted, setPosition, updateTodoTitle } from '../data';
import type { TodoRecord } from '../powersync/schema';

type Todo = TodoRecord & { id: string };

const props = defineProps<{ listId: string | null }>();
const { db } = useSession();

const params = computed(() => [props.listId ?? '']);
const { data: todos } = useQuery<Todo>('SELECT * FROM todos WHERE list_id = ? ORDER BY position, created_at, id', params);

const title = ref('');
const dragging = ref<string | null>(null);

async function add() {
  if (!props.listId) return;
  await createTodo(db, props.listId, title.value.trim() || `Todo ${new Date().toLocaleTimeString()}`);
  title.value = '';
}

async function edit(todo: Todo) {
  const next = prompt('Title', todo.title ?? '');
  if (next !== null) await updateTodoTitle(db, todo.id, next);
}

/**
 * Drops `dragging` before `target` (or at the end). Writes one PATCH of `position` only,
 * using the midpoint between neighbours so no other rows change.
 */
async function drop(target: Todo | null) {
  const id = dragging.value;
  dragging.value = null;
  if (!id || id === target?.id) return;
  const rest = todos.value.filter((t) => t.id !== id);
  const index = target ? rest.findIndex((t) => t.id === target.id) : rest.length;
  const before = rest[index - 1]?.position ?? null;
  const after = rest[index]?.position ?? null;
  let position: number;
  if (before == null && after == null) position = 1;
  else if (before == null) position = after! - 1;
  else if (after == null) position = before + 1;
  else position = (before + after) / 2;
  await setPosition(db, id, position);
}
</script>

<template>
  <section class="panel">
    <h2>Todos</h2>
    <p v-if="!listId" class="muted">Select a list.</p>
    <template v-else>
      <form class="row" @submit.prevent="add">
        <input v-model="title" placeholder="New todo" class="grow" />
        <button class="primary" type="submit">Add</button>
      </form>
      <ul class="todos" @dragover.prevent @drop.prevent="drop(null)">
        <li
          v-for="todo in todos"
          :key="todo.id"
          draggable="true"
          :class="{ dragging: dragging === todo.id }"
          @dragstart="dragging = todo.id"
          @dragend="dragging = null"
          @dragover.prevent
          @drop.prevent.stop="drop(todo)"
        >
          <span class="handle" title="Drag to reorder">⠿</span>
          <input type="checkbox" :checked="!!todo.completed" @change="setCompleted(db, todo.id, !todo.completed)" />
          <span class="title" :class="{ done: !!todo.completed }">
            {{ todo.title ?? '(null title)' }}
            <span class="muted mono">pos {{ todo.position }}</span>
          </span>
          <button @click="edit(todo)">Edit</button>
          <button class="danger" @click="deleteTodo(db, todo.id)">Delete</button>
        </li>
        <li v-if="!todos.length" class="muted">No todos.</li>
      </ul>
    </template>
  </section>
</template>

<style scoped>
.grow {
  flex: 1;
}
.todos {
  list-style: none;
  padding: 0;
  margin: 12px 0 0;
}
.todos li {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px;
  border-bottom: 1px solid var(--border);
}
.todos li.dragging {
  opacity: 0.4;
}
.handle {
  cursor: grab;
  color: var(--muted);
}
.title {
  flex: 1;
}
.done {
  text-decoration: line-through;
  color: var(--muted);
}
</style>
