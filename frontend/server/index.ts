import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express, { type Request, type Response } from 'express';
import { config } from './config.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const production = process.env.NODE_ENV === 'production';

// Dead-letter sink: the write-API override of onDeadLetter POSTs here (write-api-overrides/).
// In memory only; this is an observation window, not storage.
const deadLetters: { receivedAt: string; entry: unknown }[] = [];

const BACKEND_UNREACHABLE = `The Rails backend is not reachable at ${config.backendUrl}. Start it (docker compose up in backend/) or set BACKEND_URL.`;

/** GET against the Rails backend. Throws with a readable message when it is down. */
async function backendGet(pathAndQuery: string): Promise<globalThis.Response> {
  try {
    return await fetch(`${config.backendUrl}${pathAndQuery}`, { signal: AbortSignal.timeout(10_000) });
  } catch (error) {
    throw new Error(`${BACKEND_UNREACHABLE} (${error instanceof Error ? error.message : String(error)})`);
  }
}

const app = express();
app.use(express.json({ limit: '5mb' }));

// The write API's onDeadLetter runs server-side; CORS is for opening the UI under another host name.
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'content-type, authorization');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
  if (req.method === 'OPTIONS') return void res.sendStatus(204);
  next();
});

/**
 * Token request (GET /api/auth/token?user_id=...), answered by the Rails backend, which signs the
 * token. Proxied only so the browser can call it same-origin; writes do NOT go through this
 * server: the connector posts to the write API directly (VITE_BACKEND_URL below).
 */
app.get('/api/auth/token', async (req: Request, res: Response) => {
  try {
    const upstream = await backendGet(req.originalUrl);
    res.status(upstream.status).type(upstream.headers.get('content-type') ?? 'application/json').send(await upstream.text());
  } catch (error) {
    res.status(502).json({ message: error instanceof Error ? error.message : String(error) });
  }
});

/** What the UI needs at startup: the test users (owned by the backend) and the URLs in use. */
app.get('/api/config', async (_req, res) => {
  try {
    const upstream = await backendGet('/api/users');
    if (!upstream.ok) throw new Error(`backend answered ${upstream.status} for /api/users`);
    const { users } = (await upstream.json()) as { users: unknown[] };
    res.json({ writeApiUrl: config.writeApiUrl, powersyncUrl: config.powersyncUrl, backendUrl: config.backendUrl, users });
  } catch (error) {
    res.status(502).json({ message: error instanceof Error ? error.message : String(error) });
  }
});

app.post('/api/dead-letters', (req, res) => {
  deadLetters.unshift({ receivedAt: new Date().toISOString(), entry: req.body });
  deadLetters.length = Math.min(deadLetters.length, 500);
  console.log('[dead-letter]', JSON.stringify(req.body));
  res.status(204).end();
});
app.get('/api/dead-letters', (_req, res) => void res.json(deadLetters));
app.delete('/api/dead-letters', (_req, res) => {
  deadLetters.length = 0;
  res.status(204).end();
});

// The reference connector reads these through import.meta.env; Vite picks up VITE_* from
// process.env. Its "backend" is the write API itself: the browser posts uploads straight to it.
process.env.VITE_BACKEND_URL = config.writeApiUrl;
process.env.VITE_POWERSYNC_URL = config.powersyncUrl;

if (production) {
  const { build } = await import('vite');
  await build({ root, logLevel: 'warn' });
  const dist = path.join(root, 'dist');
  app.use(express.static(dist));
  app.get('/{*path}', (_req, res) => res.sendFile(path.join(dist, 'index.html')));
} else {
  const { createServer } = await import('vite');
  const vite = await createServer({ root, server: { middlewareMode: true }, appType: 'spa' });
  app.use(vite.middlewares);
}

app.listen(config.port, async () => {
  console.log(`Frontend on ${config.origin}${production ? '' : ' (dev, Vite middleware)'}`);
  console.log(`  Tokens:     ${config.backendUrl} (Rails; signing key in ../keys/jwks.json)`);
  console.log(`  Write API:  ${config.writeApiUrl} (the browser posts uploads directly to it)`);
  console.log(`  PowerSync:  ${config.powersyncUrl}`);
  try {
    await backendGet('/up');
  } catch (error) {
    console.warn(`\nWARNING: ${error instanceof Error ? error.message : String(error)}\n`);
  }
});
