import AsyncStorage from '@react-native-async-storage/async-storage';

import { maskSms } from './lib/smsParser';

const KEY = 'errors.v1';
const MAX = 50;

export interface LoggedError {
  at: number;
  where: string;
  message: string;
  detail?: string;
}

let pending: Promise<void> = Promise.resolve();

/** Records an error on this phone only (no network). Numbers are masked like shared alerts. */
export function logError(where: string, err: unknown, detail?: string): void {
  const message = maskSms(err instanceof Error ? err.message : String(err)).slice(0, 300);
  const stack = err instanceof Error && err.stack ? err.stack.split('\n').slice(0, 4).join('\n') : undefined;
  const entry: LoggedError = {
    at: Date.now(),
    where,
    message,
    detail: [detail ? maskSms(detail).slice(0, 300) : '', stack ?? ''].filter(Boolean).join('\n') || undefined,
  };
  // Serialise writes so concurrent errors don't overwrite each other.
  pending = pending.then(async () => {
    try {
      const list = await getErrors();
      list.unshift(entry);
      await AsyncStorage.setItem(KEY, JSON.stringify(list.slice(0, MAX)));
    } catch {
      // storage unavailable: nothing more we can do
    }
  });
}

export async function getErrors(): Promise<LoggedError[]> {
  try {
    const v = await AsyncStorage.getItem(KEY);
    return v ? (JSON.parse(v) as LoggedError[]) : [];
  } catch {
    return [];
  }
}

export async function clearErrors(): Promise<void> {
  await AsyncStorage.removeItem(KEY).catch(() => {});
}

export function formatErrors(list: LoggedError[]): string {
  return list
    .map((e) => `${new Date(e.at).toISOString()} [${e.where}] ${e.message}${e.detail ? '\n  ' + e.detail.replace(/\n/g, '\n  ') : ''}`)
    .join('\n\n');
}

/** Sends uncaught JS errors to the log, then on to React Native's default handler. */
export function installGlobalErrorHandler(): void {
  const eu = (globalThis as { ErrorUtils?: { getGlobalHandler: () => (e: unknown, fatal?: boolean) => void; setGlobalHandler: (h: (e: unknown, fatal?: boolean) => void) => void } }).ErrorUtils;
  if (!eu) return;
  const prev = eu.getGlobalHandler();
  eu.setGlobalHandler((e, fatal) => {
    logError(fatal ? 'crash' : 'uncaught', e);
    prev(e, fatal);
  });
}
