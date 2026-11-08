import { DISCRETIONARY, NON_SPEND } from './categorizer';
import type { Insight, Transaction } from './types';

const DAY = 86_400_000;

export const isSpend = (t: Transaction) => t.direction === 'debit' && !NON_SPEND.has(t.category);
export const isIncome = (t: Transaction) =>
  t.direction === 'credit' && ['Salary', 'Income', 'Interest & Dividends'].includes(t.category);
export const isInvestment = (t: Transaction) => t.direction === 'debit' && t.category === 'Investments';

export function monthKey(ms: number): string {
  const d = new Date(ms);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
}

const sum = (xs: Transaction[]) => xs.reduce((s, t) => s + t.amount, 0);

export interface MonthSummary {
  month: string;
  spend: number;
  income: number;
  invested: number;
}

export function monthlySummary(txns: Transaction[], months = 6, now = Date.now()): MonthSummary[] {
  const out: MonthSummary[] = [];
  const d = new Date(now);
  for (let i = months - 1; i >= 0; i--) {
    const key = monthKey(new Date(d.getFullYear(), d.getMonth() - i, 1).getTime());
    const inMonth = txns.filter((t) => monthKey(t.date) === key);
    out.push({
      month: key,
      spend: sum(inMonth.filter(isSpend)),
      income: sum(inMonth.filter(isIncome)),
      invested: sum(inMonth.filter(isInvestment)),
    });
  }
  return out;
}

export function byCategory(txns: Transaction[]): { category: string; amount: number; count: number }[] {
  const m = new Map<string, { amount: number; count: number }>();
  for (const t of txns.filter(isSpend)) {
    const e = m.get(t.category) ?? { amount: 0, count: 0 };
    e.amount += t.amount;
    e.count += 1;
    m.set(t.category, e);
  }
  return [...m.entries()].map(([category, v]) => ({ category, ...v })).sort((a, b) => b.amount - a.amount);
}

export function byMerchant(txns: Transaction[], limit = 10): { merchant: string; amount: number; count: number }[] {
  const m = new Map<string, { amount: number; count: number }>();
  for (const t of txns.filter(isSpend)) {
    const k = t.merchant || '(unknown)';
    const e = m.get(k) ?? { amount: 0, count: 0 };
    e.amount += t.amount;
    e.count += 1;
    m.set(k, e);
  }
  return [...m.entries()]
    .map(([merchant, v]) => ({ merchant, ...v }))
    .sort((a, b) => b.amount - a.amount)
    .slice(0, limit);
}

export const inr = (n: number) =>
  '₹' + Math.round(n).toLocaleString('en-IN', { maximumFractionDigits: 0 });

// ---------------------------------------------------------------------------
// Recurring payments (subscriptions, memberships, autopays)
// ---------------------------------------------------------------------------

export interface Recurring {
  merchant: string;
  category: string;
  amount: number; // typical charge
  periodDays: number;
  monthlyCost: number;
  lastCharged: number;
  occurrences: number;
  ids: string[];
}

const normMerchant = (m: string) => m.toLowerCase().replace(/[^a-z]/g, '');
const median = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length ? s[Math.floor(s.length / 2)] : 0;
};

export function findRecurring(txns: Transaction[], now = Date.now()): Recurring[] {
  const groups = new Map<string, Transaction[]>();
  for (const t of txns) {
    if (!isSpend(t) || !t.merchant) continue;
    if (['Groceries', 'Food Delivery', 'Dining Out', 'Cabs', 'Transport', 'Cash Withdrawal', 'Shopping'].includes(t.category)) continue;
    const k = normMerchant(t.merchant);
    if (k.length < 3) continue;
    groups.set(k, [...(groups.get(k) ?? []), t]);
  }
  const out: Recurring[] = [];
  for (const list of groups.values()) {
    if (list.length < 2) continue;
    const s = [...list].sort((a, b) => a.date - b.date);
    const amt = median(s.map((t) => t.amount));
    const similar = s.filter((t) => Math.abs(t.amount - amt) <= amt * 0.15);
    if (similar.length < 2) continue;
    const gaps = similar.slice(1).map((t, i) => (t.date - similar[i].date) / DAY);
    const gap = median(gaps);
    const period = [7, 30, 91, 365].find((p) => Math.abs(gap - p) <= p * 0.2);
    if (!period) continue;
    const last = similar[similar.length - 1].date;
    if (now - last > period * 1.6 * DAY) continue; // looks cancelled already
    out.push({
      merchant: similar[similar.length - 1].merchant,
      category: similar[similar.length - 1].category,
      amount: amt,
      periodDays: period,
      monthlyCost: (amt * 30) / period,
      lastCharged: last,
      occurrences: similar.length,
      ids: similar.map((t) => t.id),
    });
  }
  return out.sort((a, b) => b.monthlyCost - a.monthlyCost);
}

// ---------------------------------------------------------------------------
// Waste detection
// ---------------------------------------------------------------------------

export function wasteInsights(all: Transaction[], now = Date.now(), windowDays = 90): Insight[] {
  const since = now - windowDays * DAY;
  const txns = all.filter((t) => t.date >= since);
  const months = windowDays / 30;
  const spend = txns.filter(isSpend);
  const totalSpend = sum(spend);
  const insights: Insight[] = [];
  if (!spend.length) return insights;
  const cat = (c: string) => spend.filter((t) => t.category === c);

  // 1. Bank / card fees and penalties: 100% avoidable.
  const fees = cat('Fees & Charges');
  if (fees.length) {
    const interest = fees.filter((t) => /interest|finance charge/i.test(t.body));
    insights.push({
      id: 'fees',
      title: `${inr(sum(fees))} lost to fees & penalties`,
      detail:
        `${fees.length} charge(s) in the last ${windowDays} days (late fees, card interest, minimum-balance, GST on charges…). ` +
        (interest.length
          ? 'You are paying credit-card interest (~36–42% a year). Clearing the full card bill every month is the single best return you can get. '
          : '') +
        'Set autopay for the full card amount and keep minimum balances to avoid these entirely.',
      severity: 'high',
      amount: sum(fees),
      monthlySaving: sum(fees) / months,
      savingKey: 'Fees & Charges',
      transactionIds: fees.map((t) => t.id),
    });
  }

  // 2. Subscriptions / recurring.
  // Rent, EMIs, insurance and utility bills recur too, but they are commitments, not waste.
  const COMMITMENTS = new Set(['Rent & Housing', 'EMI & Loans', 'Insurance', 'Bills & Utilities', 'Health', 'Education']);
  const rec = findRecurring(all, now).filter((r) => !COMMITMENTS.has(r.category));
  if (rec.length) {
    const monthly = rec.reduce((s, r) => s + r.monthlyCost, 0);
    const streaming = rec.filter((r) => /netflix|hotstar|prime|spotify|youtube|jio ?cinema|sonyliv|zee5|gaana|wynk|apple/i.test(r.merchant));
    insights.push({
      id: 'subscriptions',
      title: `${rec.length} recurring payments: ${inr(monthly)}/month`,
      detail:
        rec
          .slice(0, 8)
          .map((r) => `• ${r.merchant}: ${inr(r.amount)} every ${r.periodDays === 30 ? 'month' : r.periodDays === 365 ? 'year' : r.periodDays + ' days'}`)
          .join('\n') +
        `\n\nThat is ${inr(monthly * 12)} a year. Cancel anything you have not used in the last month.` +
        (streaming.length >= 2 ? ` You pay for ${streaming.length} streaming/music services; rotating one at a time usually covers what you watch.` : ''),
      severity: monthly > 2000 || streaming.length >= 3 ? 'medium' : 'low',
      amount: monthly * months,
      monthlySaving: streaming.length >= 2 ? streaming.slice(1).reduce((s, r) => s + r.monthlyCost, 0) : monthly * 0.25,
      savingKey: 'Subscriptions',
      transactionIds: rec.flatMap((r) => r.ids),
    });
  }

  // 3. Food delivery.
  const food = cat('Food Delivery');
  if (food.length >= 4) {
    const total = sum(food);
    const share = total / totalSpend;
    insights.push({
      id: 'food-delivery',
      title: `Food delivery: ${food.length} orders, ${inr(total / months)}/month`,
      detail:
        `Average order ${inr(total / food.length)} (${Math.round(share * 100)}% of your spending). ` +
        'Delivery fees, platform fees and menu mark-ups add 30–50% over eating the same thing at home or at the restaurant. ' +
        'Halving orders would save roughly the amount shown.',
      severity: share > 0.12 ? 'high' : share > 0.06 ? 'medium' : 'low',
      amount: total,
      monthlySaving: (total / months) * 0.5 * 0.6,
      savingKey: 'Food Delivery',
      transactionIds: food.map((t) => t.id),
    });
  }

  // 4. Dining out.
  const dining = cat('Dining Out');
  if (dining.length && sum(dining) / totalSpend > 0.08) {
    insights.push({
      id: 'dining',
      title: `Dining out is ${Math.round((sum(dining) / totalSpend) * 100)}% of spending`,
      detail: `${dining.length} visits, ${inr(sum(dining) / months)}/month. Setting a monthly dining budget of ~5% of take-home pay is a common target.`,
      severity: 'medium',
      amount: sum(dining),
      monthlySaving: (sum(dining) / months) * 0.3,
      savingKey: 'Dining Out',
      transactionIds: dining.map((t) => t.id),
    });
  }

  // 5. Cabs.
  const cabs = cat('Cabs');
  if (sum(cabs) / months > 3000) {
    insights.push({
      id: 'cabs',
      title: `Cabs & autos: ${inr(sum(cabs) / months)}/month`,
      detail: `${cabs.length} rides. Metro/bus passes or pooling for regular commutes typically cut this by a third or more.`,
      severity: sum(cabs) / totalSpend > 0.1 ? 'medium' : 'low',
      amount: sum(cabs),
      monthlySaving: (sum(cabs) / months) * 0.35,
      savingKey: 'Cabs',
      transactionIds: cabs.map((t) => t.id),
    });
  }

  // 7. Betting / real-money gaming.
  const betting = spend.filter((t) => /dream ?11|mpl\b|my11circle|rummy|poker|betting|casino|1xbet|stake\.com/i.test(t.merchant + ' ' + t.body));
  if (betting.length) {
    insights.push({
      id: 'betting',
      title: `${inr(sum(betting))} on fantasy/real-money gaming`,
      detail: 'Real-money gaming platforms keep a cut of every contest, so most players lose money over time.',
      severity: 'high',
      amount: sum(betting),
      monthlySaving: sum(betting) / months,
      savingKey: 'betting',
      transactionIds: betting.map((t) => t.id),
    });
  }

  // 8. Heavy shopping.
  const shop = cat('Shopping');
  if (sum(shop) / totalSpend > 0.2) {
    insights.push({
      id: 'shopping',
      title: `Online shopping is ${Math.round((sum(shop) / totalSpend) * 100)}% of spending`,
      detail: `${shop.length} orders, ${inr(sum(shop) / months)}/month. Unsubscribing from sale notifications and waiting a week on wishlist items usually trims 20–30%.`,
      severity: 'medium',
      amount: sum(shop),
      monthlySaving: (sum(shop) / months) * 0.25,
      savingKey: 'Shopping',
      transactionIds: shop.map((t) => t.id),
    });
  }

  // 9. Untracked cash.
  const cash = cat('Cash Withdrawal');
  if (sum(cash) / totalSpend > 0.1) {
    insights.push({
      id: 'cash',
      title: `${inr(sum(cash))} withdrawn as cash (untracked)`,
      detail: 'Cash spending is invisible to this app, so it is hard to tell whether it is wasted. Using UPI instead lets every rupee be categorised.',
      severity: 'low',
      amount: sum(cash),
      transactionIds: cash.map((t) => t.id),
    });
  }

  // 10. Category spikes: last 30 days vs the 3 months before.
  const recentStart = now - 30 * DAY;
  const baseStart = now - 120 * DAY;
  const cats = new Set(all.filter(isSpend).map((t) => t.category));
  for (const c of cats) {
    if (c === 'Fees & Charges') continue;
    const recent = sum(all.filter((t) => isSpend(t) && t.category === c && t.date >= recentStart));
    const base = sum(all.filter((t) => isSpend(t) && t.category === c && t.date >= baseStart && t.date < recentStart)) / 3;
    if (base > 0 && recent > base * 1.5 && recent - base > 2000) {
      insights.push({
        id: `spike-${c}`,
        title: `${c} up ${Math.round((recent / base - 1) * 100)}% this month`,
        detail: `${inr(recent)} in the last 30 days vs a usual ${inr(base)}/month.`,
        severity: 'medium',
        amount: recent - base,
        monthlySaving: recent - base,
        savingKey: c,
      });
    }
  }

  // 11. Small impulse purchases (runs last so it can skip categories flagged above).
  // Categories that already have their own insight are left out, so the same money isn't counted twice.
  const flagged = new Set(insights.map((i) => i.savingKey));
  const small = spend.filter((t) => DISCRETIONARY.has(t.category) && !flagged.has(t.category) && t.amount < 500);
  if (small.length >= 20) {
    insights.push({
      id: 'impulse',
      title: `${small.length} small purchases added up to ${inr(sum(small))}`,
      detail: `Purchases under ₹500 in discretionary categories (${Math.round(small.length / months)} a month). Individually tiny, together ${inr(sum(small) / months)}/month. A 24-hour rule before non-essential buys helps.`,
      severity: 'low',
      amount: sum(small),
      monthlySaving: (sum(small) / months) * 0.4,
      savingKey: 'impulse',
      transactionIds: small.map((t) => t.id),
    });
  }

  const order = { high: 0, medium: 1, low: 2 };
  return insights.sort((a, b) => order[a.severity] - order[b.severity] || (b.monthlySaving ?? 0) - (a.monthlySaving ?? 0));
}

/** Total monthly saving across insights, counting money that several insights describe only once. */
export function totalMonthlySaving(insights: Insight[]): number {
  const best = new Map<string, number>();
  for (const i of insights) {
    if (!i.monthlySaving) continue;
    const k = i.savingKey ?? i.id;
    best.set(k, Math.max(best.get(k) ?? 0, i.monthlySaving));
  }
  return [...best.values()].reduce((s, v) => s + v, 0);
}
