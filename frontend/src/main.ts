import { createApp } from 'vue';
import { createPowerSyncPlugin } from '@powersync/vue';
import App from './App.vue';
import { harness, settings, type HarnessConfig } from './state';
import { connect, openSession } from './powersync/db';
import { SESSION_KEY } from './session';
import './style.css';

async function loadConfig(): Promise<HarnessConfig> {
  const res = await fetch('/api/config');
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.message ?? `GET /api/config failed (${res.status})`);
  return body;
}

let config: HarnessConfig;
try {
  config = await loadConfig();
} catch (error) {
  // Most likely the Rails backend (token issuer and test users) is not running.
  const message = document.createElement('pre');
  message.style.cssText = 'padding:16px;white-space:pre-wrap;color:#c53030';
  message.textContent = `Cannot start: ${error instanceof Error ? error.message : String(error)}`;
  document.getElementById('app')!.append(message);
  throw error;
}
harness.config = config;

if (!config.users.some((u) => u.id === settings.userId)) settings.userId = config.users[0].id;

const session = openSession(settings.userId);
await session.db.init();

const app = createApp(App);
app.use(createPowerSyncPlugin({ database: session.db }));
app.provide(SESSION_KEY, session);
app.mount('#app');

void connect(session);
