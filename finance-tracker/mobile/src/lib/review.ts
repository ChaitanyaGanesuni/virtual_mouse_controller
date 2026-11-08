import { findRecurring, isIncome, isInvestment, isSpend } from './analysis';
import type { WorthPoint } from './history';
import type { Transaction } from './types';

const DAY = 86_400_000;

export interface Personality {
  name: string;
  emoji: string;
  line: string;
}

export interface YearReview {
  from: number;
  to: number;
  spent: number;
  income: number;
  invested: number;
  kept: number;
  savingsRate: number | null;
  payments: number;
  topCategories: { category: string; amount: number }[];
  topMerchants: { merchant: string; amount: number; count: number }[];
  mostVisited: { merchant: string; count: number } | null;
  biggest: Transaction | null;
  foodOrders: number;
  foodSpent: number;
  rides: number;
  subscriptionsYearly: number;
  feesPaid: number;
  bestMonth: { label: string; spent: number } | null;
  netWorthChange: number | null;
  personality: Personality;
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function personalityFor(r: Omit<YearReview, 'personality'>): Personality {
  const share = (c: string) => (r.spent > 0 ? (r.topCategories.find((x) => x.category === c)?.amount ?? 0) / r.spent : 0);
  if (r.savingsRate != null && r.savingsRate >= 0.35) return { name: 'The Saver', emoji: '🐿️', line: `You kept ${Math.round(r.savingsRate * 100)}% of what you earned. Future you says thanks.` };
  if (r.income > 0 && r.invested / r.income >= 0.2) return { name: 'The Investor', emoji: '📈', line: 'A fifth or more of your income went to work for you.' };
  if (share('Food Delivery') + share('Dining Out') >= 0.15) return { name: 'The Foodie', emoji: '🍜', line: `${r.foodOrders} delivery orders: your favourite apps know you well.` };
  if (share('Shopping') >= 0.15) return { name: 'The Shopper', emoji: '🛍️', line: 'Carts were filled. Wishlists were conquered.' };
  if (share('Cabs') + share('Transport') + share('Travel') >= 0.15) return { name: 'The Explorer', emoji: '🧭', line: `${r.rides} rides and trips: always on the move.` };
  if (share('Entertainment') + share('Subscriptions') >= 0.08) return { name: 'The Entertainer', emoji: '🎬', line: 'Shows, games and music: life with a soundtrack.' };
  return { name: 'The Balancer', emoji: '⚖️', line: 'No single habit dominates. Steady and sensible.' };
}

/** "Wrapped"-style summary of the last 12 months (or less, if your SMS history is shorter). */
export function yearReview(txns: Transaction[], history: WorthPoint[], now = Date.now()): YearReview {
  const from = now - 365 * DAY;
  const inYear = txns.filter((t) => t.date >= from && t.date <= now);
  const spend = inYear.filter(isSpend);
  const sum = (xs: Transaction[]) => xs.reduce((s, t) => s + t.amount, 0);
  const spent = sum(spend);
  const income = sum(inYear.filter(isIncome));
  const invested = sum(inYear.filter(isInvestment));

  const cat = new Map<string, number>();
  for (const t of spend) cat.set(t.category, (cat.get(t.category) ?? 0) + t.amount);
  const merch = new Map<string, { amount: number; count: number }>();
  for (const t of spend) {
    if (!t.merchant) continue;
    const m = merch.get(t.merchant) ?? { amount: 0, count: 0 };
    m.amount += t.amount;
    m.count += 1;
    merch.set(t.merchant, m);
  }
  const merchants = [...merch.entries()].map(([merchant, v]) => ({ merchant, ...v }));
  const discretionary = merchants.filter((m) => !spend.some((t) => t.merchant === m.merchant && ['Rent & Housing', 'EMI & Loans', 'Insurance', 'Education'].includes(t.category)));

  const months = new Map<string, number>();
  for (const t of spend) {
    const d = new Date(t.date);
    const k = `${d.getFullYear()}-${d.getMonth()}`;
    months.set(k, (months.get(k) ?? 0) + t.amount);
  }
  const thisMonth = `${new Date(now).getFullYear()}-${new Date(now).getMonth()}`;
  const full = [...months.entries()].filter(([k]) => k !== thisMonth);
  const best = full.sort((a, b) => a[1] - b[1])[0];

  const base: Omit<YearReview, 'personality'> = {
    from: Math.max(from, Math.min(...inYear.map((t) => t.date), now)),
    to: now,
    spent,
    income,
    invested,
    kept: income - spent - invested,
    savingsRate: income > 0 ? (income - spent) / income : null,
    payments: spend.length,
    topCategories: [...cat.entries()].map(([category, amount]) => ({ category, amount })).sort((a, b) => b.amount - a.amount).slice(0, 5),
    topMerchants: [...merchants].sort((a, b) => b.amount - a.amount).slice(0, 5),
    mostVisited: discretionary.length ? [...discretionary].sort((a, b) => b.count - a.count)[0] : null,
    biggest: [...spend].sort((a, b) => b.amount - a.amount)[0] ?? null,
    foodOrders: spend.filter((t) => t.category === 'Food Delivery').length,
    foodSpent: sum(spend.filter((t) => t.category === 'Food Delivery' || t.category === 'Dining Out')),
    rides: spend.filter((t) => t.category === 'Cabs').length,
    subscriptionsYearly: findRecurring(txns, now)
      .filter((r) => r.category === 'Subscriptions')
      .reduce((s, r) => s + (r.periodDays === 30 ? r.amount * 12 : (r.amount * 365) / r.periodDays), 0),
    feesPaid: sum(spend.filter((t) => t.category === 'Fees & Charges')),
    bestMonth: best ? { label: `${MONTHS[parseInt(best[0].split('-')[1], 10)]} ${best[0].split('-')[0]}`, spent: best[1] } : null,
    netWorthChange: history.length >= 2 ? history[history.length - 1].net - history[0].net : null,
  };
  return { ...base, personality: personalityFor(base) };
}
