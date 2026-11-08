import { inr, isSpend } from './analysis';
import type { Forecast } from './forecast';
import type { Account, Insight, Transaction } from './types';

const DAY = 86_400_000;

export interface Digest {
  spent: number;
  prevSpent: number;
  /** Change in everyday spending (rent, EMIs, insurance, school fees left out) vs the previous 7 days. */
  change: number | null;
  topCategory: { category: string; amount: number } | null;
  biggest: Transaction | null;
  dueSoon: { name: string; amount: number; date: number }[];
  tip: string | null;
  notification: { title: string; text: string };
}

/** Last 7 days at a glance, plus what's due in the next 7. */
export function weeklyDigest(txns: Transaction[], accounts: Account[], forecast: Forecast, waste: Insight[], now = Date.now()): Digest {
  const last7 = txns.filter((t) => isSpend(t) && t.date > now - 7 * DAY && t.date <= now);
  const prev7 = txns.filter((t) => isSpend(t) && t.date > now - 14 * DAY && t.date <= now - 7 * DAY);
  const spent = last7.reduce((s, t) => s + t.amount, 0);
  const prevSpent = prev7.reduce((s, t) => s + t.amount, 0);
  const byCat = new Map<string, number>();
  for (const t of last7) byCat.set(t.category, (byCat.get(t.category) ?? 0) + t.amount);
  const top = [...byCat.entries()].sort((a, b) => b[1] - a[1])[0];
  const biggest = [...last7].sort((a, b) => b.amount - a.amount)[0] ?? null;

  const dueSoon = [
    ...forecast.upcoming.filter((u) => u.date <= now + 7 * DAY).map((u) => ({ name: u.merchant, amount: u.amount, date: u.date })),
    ...accounts
      .filter((a) => a.kind === 'credit_card' && (a.balance ?? 0) > 0 && a.dueDate && a.dueDate >= now && a.dueDate <= now + 7 * DAY)
      .map((a) => ({ name: `${a.institution} card bill`, amount: a.balance ?? 0, date: a.dueDate! })),
  ].sort((a, b) => a.date - b.date);

  const FIXED = new Set(['Rent & Housing', 'EMI & Loans', 'Insurance', 'Education']);
  const everyday = (xs: Transaction[]) => xs.filter((t) => !FIXED.has(t.category)).reduce((s, t) => s + t.amount, 0);
  const prevEveryday = everyday(prev7);
  const change = prevEveryday > 0 ? everyday(last7) / prevEveryday - 1 : null;
  const tip = waste[0]?.title ?? null;
  const dueText = dueSoon.length ? ` · ${dueSoon.length} bill${dueSoon.length > 1 ? 's' : ''} due this week (${inr(dueSoon.reduce((s, d) => s + d.amount, 0))})` : '';
  return {
    spent,
    prevSpent,
    change,
    topCategory: top ? { category: top[0], amount: top[1] } : null,
    biggest,
    dueSoon,
    tip,
    notification: {
      title: `Your week: ${inr(spent)} spent${change != null ? ` (${change >= 0 ? '+' : ''}${Math.round(change * 100)}%)` : ''}`,
      text: `${top ? `Most on ${top[0]} (${inr(top[1])})` : 'Quiet week'}${dueText}. Open Paisa Watch for your weekly check-in.`,
    },
  };
}

/** Next Sunday 7 pm (today if it's Sunday before 7 pm). */
export function nextSundayEvening(now = Date.now()): number {
  const d = new Date(now);
  const t = new Date(d.getFullYear(), d.getMonth(), d.getDate() + ((7 - d.getDay()) % 7), 19, 0, 0);
  return t.getTime() > now ? t.getTime() : t.getTime() + 7 * DAY;
}
