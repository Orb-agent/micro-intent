import { storage } from '#imports';
import type { UiSettings } from '../src/ui/host';

export type BackendMode = 'auto' | 'live' | 'mock';

export interface Settings extends UiSettings {
  backendUrl: string;
  /** auto: use the backend, fall back to the local mock when it is unreachable. */
  backendMode: BackendMode;
}

export const DEFAULT_SETTINGS: Settings = {
  backendUrl: 'http://localhost:8080',
  backendMode: 'auto',
  largeMode: false,
  readAloud: false,
  lang: 'en',
};

export const settingsItem = storage.defineItem<Settings>('sync:settings', { fallback: DEFAULT_SETTINGS });

export async function getSettings(): Promise<Settings> {
  return { ...DEFAULT_SETTINGS, ...(await settingsItem.getValue()) };
}

export async function updateSettings(patch: Partial<Settings>): Promise<Settings> {
  const next = { ...(await getSettings()), ...patch };
  await settingsItem.setValue(next);
  return next;
}

export function watchSettings(fn: (s: Settings) => void): () => void {
  return settingsItem.watch((next) => fn({ ...DEFAULT_SETTINGS, ...next }));
}
