import 'dotenv/config';

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    console.error(`\nCannot start: set ${name} in frontend/.env (see .env.example).\n`);
    process.exit(1);
  }
  return value;
}

const port = Number(process.env.PORT ?? 5180);

export const config = {
  port,
  /** This server's origin. The reference connector's VITE_BACKEND_URL points here. */
  origin: process.env.PUBLIC_ORIGIN?.replace(/\/+$/, '') || `http://localhost:${port}`,
  /**
   * The Rails app (backend/). It issues every token, serves the signing key as a JWKS and knows the
   * test users; this server only proxies to it. Called server to server, never from the browser.
   */
  backendUrl: (process.env.BACKEND_URL?.trim() || 'http://localhost:3000').replace(/\/+$/, ''),
  /** Base URL of the write API under test, no trailing slash. Called by this server's proxy. */
  writeApiUrl: required('WRITE_API_URL').replace(/\/+$/, ''),
  /** Hosted PowerSync instance endpoint. Called from the browser (VITE_POWERSYNC_URL). */
  powersyncUrl: required('POWERSYNC_URL').replace(/\/+$/, '')
};
