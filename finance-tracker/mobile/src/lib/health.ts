import { isIncome, isInvestment, isSpend } from './analysis';
import type { Account, Holding, Transaction } from './types';

const DAY = 86_400_000;

export interface HealthPart {
  key: string;
  label: string;
  score: number; // 0..max
  max: number;
  note: string;
  /** Not scored because the data it needs (e.g. income) wasn't found in your SMS. */
  unknown?: boolean;
}

export interface Health {
  score: number; // 0..100
  grade: 'Excellent' | 'Good' | 'Fair' | 'Needs work';
  parts: HealthPart[];
  /** Set when some parts couldn't be scored; the score is scaled from the parts that could. */
  partial?: string;
}

const clamp = (v: number, lo = 0, hi = 1) => Math.max(lo, Math.min(hi, v));

/**
 * A 0–100 "money health" score from the last 90 days:
 * savings rate (30), avoidable fees (20), emergency cushion (20), investing habit (20), fund costs (10).
 */
export function moneyHealth(txns: Transaction[], accounts: Account[], holdings: Holding[], now = Date.now()): Health | null {
  const recent = txns.filter((t) => t.date >= now - 90 * DAY);
  const income = recent.filter(isIncome).reduce((s, t) => s + t.amount, 0);
  const spend = recent.filter(isSpend).reduce((s, t) => s + t.amount, 0);
  if (income <= 0 && spend <= 0) return null;
  const invested = recent.filter(isInvestment).reduce((s, t) => s + t.amount, 0);
  const fees = recent.filter((t) => t.category === 'Fees & Charges').reduce((s, t) => s + t.amount, 0);
  const cash = accounts.filter((a) => a.kind === 'bank').reduce((s, a) => s + (a.balance ?? 0), 0);
  const monthlySpend = spend / 3;

  const savingsRate = income > 0 ? (income - spend) / income : 0;
  const investRate = income > 0 ? invested / income : 0;
  const cushionMonths = monthlySpend > 0 ? cash / monthlySpend : 0;
  const mfValue = holdings.reduce((s, h) => s + h.currentValue, 0);
  const regularShare = mfValue > 0 ? holdings.filter((h) => h.plan === 'regular').reduce((s, h) => s + h.currentValue, 0) / mfValue : 0;

  const parts: HealthPart[] = [
    {
      key: 'savings',
      label: 'Savings rate',
      max: 30,
      score: Math.round(30 * clamp(savingsRate / 0.3)),
      note: income > 0 ? `${Math.round(savingsRate * 100)}% of income kept (aim 30%)` : 'Salary/income alerts not found in your SMS',
      unknown: income <= 0,
    },
    {
      key: 'fees',
      label: 'Avoidable fees',
      max: 20,
      score: Math.round(20 * clamp(1 - fees / 2000)),
      note: fees > 0 ? `₹${Math.round(fees).toLocaleString('en-IN')} in fees & penalties` : 'No fees or penalties',
    },
    {
      key: 'cushion',
      label: 'Emergency cushion',
      max: 20,
      score: Math.round(20 * clamp(cushionMonths / 6)),
      note: `${cushionMonths.toFixed(1)} months of spending in the bank (aim 6)`,
    },
    {
      key: 'investing',
      label: 'Investing habit',
      max: 20,
      score: Math.round(20 * clamp(investRate / 0.2)),
      note: income > 0 ? `${Math.round(investRate * 100)}% of income invested (aim 20%)` : 'Salary/income alerts not found in your SMS',
      unknown: income <= 0,
    },
    {
      key: 'costs',
      label: 'Fund costs',
      max: 10,
      score: Math.round(10 * clamp(1 - regularShare)),
      note: mfValue > 0 ? (regularShare > 0 ? `${Math.round(regularShare * 100)}% in Regular plans` : 'All in Direct plans') : 'No mutual funds found yet',
      unknown: mfValue <= 0,
    },
  ];
  // Parts we can't measure are left out and the rest scaled to 100, instead of counting as zero.
  const known = parts.filter((p) => !p.unknown);
  const knownMax = known.reduce((s, p) => s + p.max, 0);
  for (const p of parts) if (p.unknown) p.score = 0;
  const score = knownMax > 0 ? Math.round((known.reduce((s, p) => s + p.score, 0) / knownMax) * 100) : 0;
  const missing = parts.filter((p) => p.unknown).map((p) => p.label.toLowerCase());
  const grade = score >= 80 ? 'Excellent' : score >= 60 ? 'Good' : score >= 40 ? 'Fair' : 'Needs work';
  return { score, grade, parts, partial: missing.length ? `Not scored yet: ${missing.join(', ')}` : undefined };
}
