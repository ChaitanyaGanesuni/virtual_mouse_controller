import { requireOptionalNativeModule } from 'expo';

import type { RawSms } from '../../src/lib/types';

export type AlertMode = 'off' | 'smart' | 'all';
export interface Reminder {
  at: number;
  title: string;
  text: string;
}

interface SmsReaderNative {
  readInbox(sinceMs: number, maxCount: number): Promise<RawSms[]>;
  setAlertPrefs(mode: AlertMode, largeAmount: number, recurring: string[]): void;
  scheduleReminders(json: string): void;
  canNotify(): boolean;
}

const native = requireOptionalNativeModule<SmsReaderNative>('SmsReader');

export const smsSupported = native != null;

export async function readInbox(sinceMs: number, maxCount = 20000): Promise<RawSms[]> {
  if (!native) return [];
  return native.readInbox(sinceMs, maxCount);
}

/** Tells the background SMS receiver which alerts to raise. */
export function setAlertPrefs(mode: AlertMode, largeAmount: number, recurring: string[]): void {
  native?.setAlertPrefs(mode, largeAmount, recurring);
}

export function scheduleReminders(reminders: Reminder[]): void {
  native?.scheduleReminders(JSON.stringify(reminders));
}

export function canNotify(): boolean {
  return native?.canNotify() ?? false;
}
