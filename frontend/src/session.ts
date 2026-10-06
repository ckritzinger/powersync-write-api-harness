import { inject, type InjectionKey } from 'vue';
import type { Session } from './powersync/db';
import { harness, settings } from './state';

export const SESSION_KEY: InjectionKey<Session> = Symbol('session');

export function useSession(): Session {
  const session = inject(SESSION_KEY);
  if (!session) throw new Error('No session provided');
  return session;
}

export const currentUser = () => harness.config?.users.find((u) => u.id === settings.userId);
export const otherUser = () => harness.config?.users.find((u) => u.id !== settings.userId);
