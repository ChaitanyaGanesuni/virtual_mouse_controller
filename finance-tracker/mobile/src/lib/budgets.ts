import { inr, isSpend, monthKey } from './analysis';
import type { Transaction } from './types';

/** Monthly limit per category. */
export type Budgets = Record<string, number>;

export interface BudgetStatus {
  category: string;
  limit: number;
  spent: number;
  pct: number; // spent / limit
  /** Where this category is heading by month end at the current pace. */
  projected: number;
}

const roundUp = (v: number, to: number) => Math.ceil(v / to) * to;

function monthBounds(now: number) {
  const d = new Date(now);
  const start = new Date(d.getFullYear(), d.getMonth(), 1).getTime();
  const days = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
  const elapsed = Math.max(1, (now - start) / 86_400_000);
  return { start, days, elapsed };
}

/**
 * Suggests a limit for each regular spending category: the average of the last three full months,
 * trimmed 10% for discretionary categories (the point of a budget is to nudge down), rounded up to ₹500.
 */
export function suggestBudgets(txns: Transaction[], now = Date.now()): Budgets {
  const d = new Date(now);
  const months = [1, 2, 3].map((i) => monthKey(new Date(d.getFullYear(), d.getMonth() - i, 1).getTime()));
  const totals = new Map<string, number[]>();
  for (const t of txns) {
    if (!isSpend(t)) continue;
    const i = months.indexOf(monthKey(t.date));
    if (i < 0) continue;
    const arr = totals.get(t.category) ?? [0, 0, 0];
    arr[i] += t.amount;
    totals.set(t.category, arr);
  }
  const trim = new Set(['Food Delivery', 'Dining Out', 'Shopping', 'Entertainment', 'Cabs', 'Subscriptions', 'Travel']);
  const out: Budgets = {};
  for (const [cat, arr] of totals) {
    const active = arr.filter((v) => v > 0);
    if (active.length < 2) continue; // not a regular category
    const avg = arr.reduce((s, v) => s + v, 0) / 3;
    if (avg < 500) continue;
    out[cat] = roundUp(avg * (trim.has(cat) ? 0.9 : 1), 500);
  }
  return out;
}

export function budgetStatus(txns: Transaction[], budgets: Budgets, now = Date.now()): BudgetStatus[] {
  const { start, days, elapsed } = monthBounds(now);
  const spent = new Map<string, number>();
  for (const t of txns) if (isSpend(t) && t.date >= start && t.date <= now) spent.set(t.category, (spent.get(t.category) ?? 0) + t.amount);
  return Object.entries(budgets)
    .filter(([, limit]) => limit > 0)
    .map(([category, limit]) => {
      const s = spent.get(category) ?? 0;
      return { category, limit, spent: s, pct: s / limit, projected: (s / elapsed) * days };
    })
    .sort((a, b) => b.pct - a.pct);
}

export interface BudgetAlert {
  key: string; // month|category|threshold, so each alert fires once a month
  title: string;
  text: string;
}

/** Budgets that crossed 80% or 100% this month and haven't been alerted yet. */
export function budgetAlerts(status: BudgetStatus[], alreadySent: string[], now = Date.now()): BudgetAlert[] {
  const m = monthKey(now);
  const out: BudgetAlert[] = [];
  for (const b of status) {
    const level = b.pct >= 1 ? 100 : b.pct >= 0.8 ? 80 : 0;
    if (!level) continue;
    const key = `${m}|${b.category}|${level}`;
    if (alreadySent.includes(key)) continue;
    out.push({
      key,
      title: level === 100 ? `${b.category} budget used up` : `${b.category}: 80% of budget used`,
      text:
        level === 100
          ? `${inr(b.spent)} spent of ${inr(b.limit)} this month.`
          : `${inr(b.limit - b.spent)} left of ${inr(b.limit)} for the rest of the month.`,
    });
  }
  return out;
}
