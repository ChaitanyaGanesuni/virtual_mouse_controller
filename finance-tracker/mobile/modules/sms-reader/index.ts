import { requireOptionalNativeModule } from 'expo';

import type { RawSms } from '../../src/lib/types';

interface SmsReaderNative {
  readInbox(sinceMs: number, maxCount: number): Promise<RawSms[]>;
}

const native = requireOptionalNativeModule<SmsReaderNative>('SmsReader');

export const smsSupported = native != null;

export async function readInbox(sinceMs: number, maxCount = 20000): Promise<RawSms[]> {
  if (!native) return [];
  return native.readInbox(sinceMs, maxCount);
}
