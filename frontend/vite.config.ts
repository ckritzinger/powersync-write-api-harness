import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

const root = fileURLToPath(new URL('.', import.meta.url));
// src/example-client is a symlink into a powersync-reference-write-implementation checkout (see scripts/link-example-client.sh).
const exampleClient = realpathSync(fileURLToPath(new URL('./src/example-client', import.meta.url)));

// Served by server/index.ts (Vite middleware in dev, static build in production); one origin.
export default defineConfig({
  plugins: [vue()],
  resolve: {
    // Vite follows the symlink to powersync-reference-write-implementation, which has no node_modules. Resolve the
    // reference connector's bare imports from this app's root instead.
    dedupe: ['@powersync/web', 'openapi-fetch', 'uuid']
  },
  server: {
    fs: { allow: [root, exampleClient] }
  },
  optimizeDeps: {
    // These packages ship web workers and WASM; pre-bundling breaks their asset URLs.
    exclude: ['@powersync/web', '@journeyapps/wa-sqlite']
  },
  worker: { format: 'es' },
  build: { target: 'es2022' }
});
