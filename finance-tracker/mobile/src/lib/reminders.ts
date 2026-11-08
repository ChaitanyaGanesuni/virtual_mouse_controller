import { inr } from './analysis';
import type { Account } from './types';

const DAY = 86_400_000;

export interface PlannedReminder {
  at: number;
  title: string;
  text: string;
}

const atTime = (day: number, hour: number) => {
  const d = new Date(day);
  d.setHours(hour, 0, 0, 0);
  return d.getTime();
};

/**
 * For every card with an unpaid statement and a known due date, remind 3 days before, the day
 * before, and on the morning of the due date. Paid-off cards get no reminders.
 */
export function planReminders(accounts: Account[], now = Date.now()): PlannedReminder[] {
  const out: PlannedReminder[] = [];
  for (const a of accounts) {
    if (a.kind !== 'credit_card' || a.dueDate == null || a.balance == null || a.balance <= 0) continue;
    const name = `${a.institution} card ••${a.last4 || '??'}`;
    const due = new Date(a.dueDate).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
    const min = a.minDue ? ` (minimum ${inr(a.minDue)})` : '';
    const steps: [number, string][] = [
      [3, `${name}: ${inr(a.balance)} due on ${due}`],
      [1, `${name}: ${inr(a.balance)} due tomorrow`],
      [0, `${name}: ${inr(a.balance)} due today`],
    ];
    for (const [daysBefore, title] of steps) {
      const at = atTime(a.dueDate - daysBefore * DAY, daysBefore === 0 ? 9 : 10);
      if (at <= now) continue;
      out.push({
        at,
        title,
        text: `Pay the full amount${min} to avoid late fees and ~40% a year interest.`,
      });
    }
  }
  return out.sort((x, y) => x.at - y.at);
}
