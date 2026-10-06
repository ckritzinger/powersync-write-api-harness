<script setup lang="ts">
import { onMounted, onUnmounted, ref } from 'vue';
import { useSession } from '../session';

interface CrudRow {
  id: number;
  tx_id: number | null;
  data: string;
}

const { db } = useSession();
const rows = ref<CrudRow[]>([]);
let timer: ReturnType<typeof setInterval> | undefined;

// ps_crud is the SDK's internal upload queue; polled because watched queries track user tables.
async function refresh() {
  rows.value = await db.getAll<CrudRow>('SELECT id, tx_id, data FROM ps_crud ORDER BY id');
}

onMounted(() => {
  void refresh();
  timer = setInterval(refresh, 1000);
});
onUnmounted(() => clearInterval(timer));

const parse = (data: string) => {
  try {
    return JSON.parse(data);
  } catch {
    return data;
  }
};
</script>

<template>
  <div>
    <p class="muted">
      Local upload queue (<span class="mono">ps_crud</span>), {{ rows.length }} operations in
      {{ new Set(rows.map((r) => r.tx_id)).size }} transactions. The head transaction is what the next upload sends.
    </p>
    <table class="mono">
      <thead>
        <tr><th>op id</th><th>tx</th><th>op</th><th>table</th><th>row id</th><th>data</th></tr>
      </thead>
      <tbody>
        <tr v-for="row in rows" :key="row.id">
          <td>{{ row.id }}</td>
          <td>{{ row.tx_id }}</td>
          <td>{{ parse(row.data).op }}</td>
          <td>{{ parse(row.data).type }}</td>
          <td :title="parse(row.data).id">{{ String(parse(row.data).id).slice(0, 8) }}</td>
          <td class="data">{{ JSON.stringify(parse(row.data).data ?? {}) }}</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<style scoped>
table {
  width: 100%;
  border-collapse: collapse;
}
th,
td {
  text-align: left;
  padding: 3px 4px;
  border-bottom: 1px solid var(--border);
  vertical-align: top;
}
.data {
  word-break: break-all;
}
</style>
