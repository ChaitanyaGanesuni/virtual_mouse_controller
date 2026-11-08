import AsyncStorage from '@react-native-async-storage/async-storage';
import * as DocumentPicker from 'expo-document-picker';
import { File, Paths } from 'expo-file-system';
import * as Sharing from 'expo-sharing';

import { BACKUP_KEYS, makeBackup, readBackup } from './lib/backupFormat';

export { BACKUP_KEYS };

/** Writes the backup to a file and opens the share sheet (Drive, email, WhatsApp to yourself…). */
export async function exportBackup(): Promise<void> {
  const entries = await AsyncStorage.multiGet(BACKUP_KEYS);
  const backup = makeBackup(entries);
  const stamp = new Date().toISOString().slice(0, 10);
  const file = new File(Paths.cache, `paisa-watch-backup-${stamp}.json`);
  if (file.exists) file.delete();
  file.create();
  file.write(JSON.stringify(backup, null, 1));
  await Sharing.shareAsync(file.uri, { mimeType: 'application/json', dialogTitle: 'Save your Paisa Watch backup' });
}

/** Lets you pick a backup file and restores it. Returns how many settings were restored, or null if cancelled. */
export async function importBackup(): Promise<number | null> {
  const res = await DocumentPicker.getDocumentAsync({ type: ['application/json', 'text/plain', '*/*'], copyToCacheDirectory: true });
  if (res.canceled || !res.assets?.length) return null;
  const text = await new File(res.assets[0].uri).text();
  const pairs = readBackup(text);
  if (!pairs.length) throw new Error('The backup is empty.');
  await AsyncStorage.multiSet(pairs);
  return pairs.length;
}
