import { findRecurring, isIncome, isInvestment, isSpend } from './analysis';
import type { Transaction } from './types';

const DAY = 86_400_000;

/** Monthly bills land on the same date each month (clamped to the month's last day), not every 30 days. */
export function nextMonthly(last: number): number {
  const d = new Date(last);
  const target = new Date(d.getFullYear(), d.getMonth() + 1, 1, d.getHours(), d.getMinutes());
  const lastDay = new Date(target.getFullYear(), target.getMonth() + 1, 0).getDate();
  target.setDate(Math.min(d.getDate(), lastDay));
  return target.getTime();
}

export interface Forecast {
  spentSoFar: number;
  projectedSpend: number;
  upcoming: { merchant: string; category: string; amount: number; date: number }[];
  dailyRate: number; // day-to-day (non-recurring) spending per day
  incomeSoFar: number;
  expectedIncome: number; // includes salary not yet received this month
  invested: number;
  leftAtMonthEnd: number;
  daysLeft: number;
  monthEnd: number;
}

/**
 * Month-end projection: what you've spent, plus recurring payments still due this month,
 * plus your usual day-to-day spending for the days that remain.
 */
export function monthForecast(txns: Transaction[], now = Date.now()): Forecast {
  const d = new Date(now);
  const start = new Date(d.getFullYear(), d.getMonth(), 1).getTime();
  const end = new Date(d.getFullYear(), d.getMonth() + 1, 0, 23, 59, 59).getTime();
  const prevStart = new Date(d.getFullYear(), d.getMonth() - 1, 1).getTime();
  const daysLeft = Math.max(0, Math.ceil((end - now) / DAY));
  const thisMonth = txns.filter((t) => t.date >= start && t.date <= now);

  const spentSoFar = thisMonth.filter(isSpend).reduce((s, t) => s + t.amount, 0);

  // Monthly recurring payments not yet charged this month.
  const recurring = findRecurring(txns, now).filter((r) => r.periodDays === 30);
  const recurringIds = new Set(recurring.flatMap((r) => r.ids));
  const upcoming = recurring
    .map((r) => ({ merchant: r.merchant, category: r.category, amount: r.amount, date: nextMonthly(r.lastCharged) }))
    .filter((u) => u.date > now && u.date <= end && !thisMonth.some((t) => recurringIds.has(t.id) && t.merchant === u.merchant));

  // Day-to-day spending rate over the last 60 days, excluding recurring bills and one-off large payments.
  const window = txns.filter((t) => isSpend(t) && t.date >= now - 60 * DAY && t.date <= now && !recurringIds.has(t.id));
  const amounts = window.map((t) => t.amount).sort((a, b) => a - b);
  const cap = amounts.length >= 10 ? amounts[Math.floor(amounts.length * 0.95)] : Infinity;
  const dailyRate = window.reduce((s, t) => s + Math.min(t.amount, cap), 0) / 60;

  const projectedSpend = spentSoFar + upcoming.reduce((s, u) => s + u.amount, 0) + dailyRate * daysLeft;

  const incomeSoFar = thisMonth.filter(isIncome).reduce((s, t) => s + t.amount, 0);
  const lastMonthIncome = txns.filter((t) => isIncome(t) && t.date >= prevStart && t.date < start).reduce((s, t) => s + t.amount, 0);
  const expectedIncome = Math.max(incomeSoFar, incomeSoFar > 0 ? incomeSoFar : lastMonthIncome);
  const invested = thisMonth.filter(isInvestment).reduce((s, t) => s + t.amount, 0);

  return {
    spentSoFar,
    projectedSpend,
    upcoming: upcoming.sort((a, b) => a.date - b.date),
    dailyRate,
    incomeSoFar,
    expectedIncome,
    invested,
    leftAtMonthEnd: expectedIncome - projectedSpend - invested,
    daysLeft,
    monthEnd: end,
  };
}
