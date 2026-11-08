import { findRecurring } from './analysis';
import type { BillNotice } from './ledger';
import type { Transaction } from './types';

const DAY = 86_400_000;

export interface PriceChange {
  id: string; // stable: merchant + date of the new charge
  kind: 'price-rise' | 'bill-spike';
  name: string;
  category: string;
  from: number;
  to: number;
  pct: number;
  /** Extra cost per year at the new price (price rises) or this bill's excess (spikes). */
  impact: number;
  date: number;
}

const norm = (m: string) => m.toLowerCase().replace(/[^a-z]/g, '');
const median = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length ? s[Math.floor(s.length / 2)] : 0;
};

/**
 * Subscriptions that now cost more (latest charge > recent typical by 5% and ₹20+), and bills well above
 * their usual (latest > 1.3× the average of the previous three, and ₹300+ more).
 */
export function priceChanges(txns: Transaction[], bills: BillNotice[] = [], now = Date.now()): PriceChange[] {
  const out: PriceChange[] = [];
  const debits = txns.filter((t) => t.direction === 'debit' && t.merchant).sort((a, b) => a.date - b.date);
  const byMerchant = new Map<string, Transaction[]>();
  for (const t of debits) byMerchant.set(norm(t.merchant), [...(byMerchant.get(norm(t.merchant)) ?? []), t]);

  // Price rises on recurring payments.
  for (const r of findRecurring(txns, now)) {
    if (['Rent & Housing', 'EMI & Loans', 'Bills & Utilities'].includes(r.category)) continue;
    const list = byMerchant.get(norm(r.merchant)) ?? [];
    if (list.length < 3) continue;
    const latest = list[list.length - 1];
    if (latest.date < now - 45 * DAY) continue;
    const before = median(list.slice(-4, -1).map((t) => t.amount));
    if (latest.amount > before * 1.05 && latest.amount - before >= 20) {
      out.push({
        id: `rise|${norm(r.merchant)}|${latest.key}`,
        kind: 'price-rise',
        name: r.merchant,
        category: r.category,
        from: before,
        to: latest.amount,
        pct: latest.amount / before - 1,
        impact: r.periodDays === 30 ? (latest.amount - before) * 12 : ((latest.amount - before) * 365) / r.periodDays,
        date: latest.date,
      });
    }
  }

  // Bills well above usual: from payments categorised as bills, and from bill-due SMS.
  const seen = new Set<string>();
  const spike = (name: string, category: string, amounts: { amount: number; date: number; key: string }[]) => {
    if (amounts.length < 4) return;
    const latest = amounts[amounts.length - 1];
    if (latest.date < now - 45 * DAY) return;
    const avg = amounts.slice(-4, -1).reduce((s, x) => s + x.amount, 0) / 3;
    if (latest.amount > avg * 1.3 && latest.amount - avg >= 300 && !seen.has(norm(name))) {
      seen.add(norm(name));
      out.push({ id: `spike|${norm(name)}|${latest.key}`, kind: 'bill-spike', name, category, from: avg, to: latest.amount, pct: latest.amount / avg - 1, impact: latest.amount - avg, date: latest.date });
    }
  };
  const billsBy = new Map<string, BillNotice[]>();
  for (const b of bills) billsBy.set(b.biller, [...(billsBy.get(b.biller) ?? []), b]);
  for (const [name, list] of billsBy) spike(name, 'Bills & Utilities', list.map((b) => ({ amount: b.amount, date: b.date, key: b.id })));
  for (const [, list] of byMerchant) {
    const bl = list.filter((t) => t.category === 'Bills & Utilities');
    if (bl.length) spike(bl[0].merchant, 'Bills & Utilities', bl.map((t) => ({ amount: t.amount, date: t.date, key: t.key })));
  }
  return out.sort((a, b) => b.date - a.date);
}
