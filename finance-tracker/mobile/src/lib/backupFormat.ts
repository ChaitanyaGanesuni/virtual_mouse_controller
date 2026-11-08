/**
 * Everything you've told the app (category fixes, budgets, goals, settings). Transactions themselves
 * are not included: they are rebuilt from your SMS on the new phone.
 */
export const BACKUP_KEYS = [
  'rules.v1',
  'overrides.v1',
  'assumptions.v1',
  'alerts.v1',
  'budgets.v1',
  'lock.v1',
  'secure.v1',
  'goals.v1',
  'subs.v1',
  'subsReviewedAt.v1',
  'digest.v1',
  'tax.v1',
  'rentProfile.v1',
  'guardDismissed.v1',
];

interface BackupFile {
  app: 'paisa-watch';
  version: 1;
  createdAt: number;
  data: Record<string, string>;
}

export function makeBackup(entries: readonly (readonly [string, string | null])[], now = Date.now()): BackupFile {
  const data: Record<string, string> = {};
  for (const [k, v] of entries) if (v != null && BACKUP_KEYS.includes(k)) data[k] = v;
  return { app: 'paisa-watch', version: 1, createdAt: now, data };
}

/** Validates a backup file and returns the key/value pairs to restore (unknown keys are ignored). */
export function readBackup(text: string): [string, string][] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error("That file isn't a Paisa Watch backup.");
  }
  const b = parsed as Partial<BackupFile>;
  if (!b || b.app !== 'paisa-watch' || typeof b.data !== 'object' || b.data == null) throw new Error("That file isn't a Paisa Watch backup.");
  if (b.version !== 1) throw new Error('This backup is from a newer version of Paisa Watch. Update the app first.');
  const out: [string, string][] = [];
  for (const [k, v] of Object.entries(b.data)) {
    if (!BACKUP_KEYS.includes(k) || typeof v !== 'string') continue;
    try {
      JSON.parse(v); // every stored value is JSON
    } catch {
      continue;
    }
    out.push([k, v]);
  }
  return out;
}
