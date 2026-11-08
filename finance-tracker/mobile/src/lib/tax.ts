import type { Holding, MfOrder, Transaction } from './types';

const DAY = 86_400_000;

export type Regime = 'new' | 'old';

/** Indian financial year (1 Apr – 31 Mar) containing `now`. */
export function financialYear(now = Date.now()) {
  const d = new Date(now);
  const y = d.getMonth() >= 3 ? d.getFullYear() : d.getFullYear() - 1;
  return {
    start: new Date(y, 3, 1).getTime(),
    end: new Date(y + 1, 2, 31, 23, 59, 59).getTime(),
    label: `FY ${y}-${String((y + 1) % 100).padStart(2, '0')}`,
  };
}

export interface DeductionItem {
  section: string;
  label: string;
  amount: number;
  txnIds: string[];
}

export interface DeductionGroup {
  section: '80C' | '80CCD(1B)' | '80D' | '80TTA';
  title: string;
  limit: number;
  claimed: number; // min(total, limit)
  total: number;
  items: DeductionItem[];
  hint: string;
}

const ELSS_RE = /elss|tax ?saver|long term equity|tax relief|tax advantage/i;
const LIFE_RE = /\blife\b|\blic\b|term plan|max life|tata aia|hdfc life|icici pru|sbi life|bajaj allianz life|kotak life|aditya birla sun life insurance/i;
const HEALTH_RE = /health|mediclaim|star health|care health|niva bupa|hdfc ergo|aditya birla health|acko|digit|manipal ?cigna|bajaj allianz general/i;
const TUITION_RE = /school|tuition|vidyalaya|public school|convent|academy|high school/i;
const PPF_RE = /\bppf\b|public provident/i;
const NPS_RE = /\bnps\b|pfrda|national pension|\bcra\b|protean/i;
const SAVINGS_INTEREST_RE = /interest|int\.? ?(?:pd|cr|paid|credited)|\bint\b/i;

const sumOf = (xs: { amount: number }[]) => xs.reduce((s, x) => s + x.amount, 0);

export function deductions(txns: Transaction[], orders: MfOrder[], now = Date.now()): DeductionGroup[] {
  const { start, end } = financialYear(now);
  const inFy = txns.filter((t) => t.date >= start && t.date <= end);
  const debits = inFy.filter((t) => t.direction === 'debit');
  const item = (section: string, label: string, ts: Transaction[]): DeductionItem[] =>
    ts.length ? [{ section, label, amount: sumOf(ts), txnIds: ts.map((t) => t.id) }] : [];

  const elss = orders.filter((o) => o.date >= start && o.date <= end && o.amount > 0 && ELSS_RE.test(o.scheme));
  const c80: DeductionItem[] = [
    ...(elss.length ? [{ section: '80C', label: 'ELSS tax-saver funds', amount: elss.reduce((s, o) => s + o.amount, 0), txnIds: [] }] : []),
    ...item('80C', 'PPF deposits', debits.filter((t) => PPF_RE.test(t.body + t.merchant))),
    ...item('80C', 'Life insurance premiums', debits.filter((t) => t.category === 'Insurance' && LIFE_RE.test(t.body + t.merchant) && !HEALTH_RE.test(t.body + t.merchant))),
    ...item('80C', "Children's tuition fees", debits.filter((t) => t.category === 'Education' && TUITION_RE.test(t.body + t.merchant))),
  ];
  const nps = item('80CCD(1B)', 'NPS contributions', debits.filter((t) => NPS_RE.test(t.body + t.merchant)));
  const health = item('80D', 'Health insurance premiums', debits.filter((t) => t.category === 'Insurance' && HEALTH_RE.test(t.body + t.merchant)));
  const interest = item(
    '80TTA',
    'Savings account interest',
    inFy.filter((t) => t.direction === 'credit' && t.accountKind === 'bank' && t.category === 'Interest & Dividends' && SAVINGS_INTEREST_RE.test(t.body)),
  );

  const group = (section: DeductionGroup['section'], title: string, limit: number, items: DeductionItem[], hint: string): DeductionGroup => {
    const total = sumOf(items);
    return { section, title, limit, total, claimed: Math.min(total, limit), items, hint };
  };
  return [
    group('80C', 'Investments & premiums (80C)', 150_000, c80, 'EPF and home-loan principal also count but aren\'t in SMS. Check your payslip and loan statement.'),
    group('80CCD(1B)', 'Extra NPS (80CCD(1B))', 50_000, nps, 'Over and above the ₹1.5L 80C limit.'),
    group('80D', 'Health insurance (80D)', 25_000, health, '₹25k for you & family; another ₹25k–50k for parents\' policy.'),
    group('80TTA', 'Savings interest (80TTA)', 10_000, interest, 'Interest on savings accounts up to ₹10k is deductible.'),
  ];
}

// ---------------------------------------------------------------- capital gains

export const LTCG_EXEMPTION = 125_000; // Sec 112A, equity, per FY (from 23 Jul 2024)

interface Lot {
  date: number;
  units: number;
  nav: number;
}

export interface GainsSummary {
  /** Long-term (held > 1 year) equity gains already booked by selling this FY. */
  realisedLongTerm: number;
  realisedShortTerm: number;
  /** Unrealised gains on equity lots held > 1 year: what could be booked now. */
  unrealisedLongTerm: number;
  unrealisedShortTerm: number;
  /** How much long-term gain can still be booked tax-free this FY. */
  harvestable: number;
  /** Short-term lots that become long-term within 60 days (worth waiting for). */
  maturingSoon: { scheme: string; date: number; gain: number }[];
}

const isEquity = (h: Holding) => h.assetClass === 'equity' || (h.assetClass === 'hybrid' && /equity|aggressive|arbitrage|balanced advantage/i.test(h.scheme));

/** FIFO lots per fund: purchases add lots, redemptions consume the oldest first. */
export function capitalGains(holdings: Holding[], now = Date.now()): GainsSummary {
  const { start, end } = financialYear(now);
  const out: GainsSummary = { realisedLongTerm: 0, realisedShortTerm: 0, unrealisedLongTerm: 0, unrealisedShortTerm: 0, harvestable: 0, maturingSoon: [] };
  for (const h of holdings.filter(isEquity)) {
    const lots: Lot[] = [];
    for (const o of [...h.orders].sort((a, b) => a.date - b.date)) {
      if (o.units > 0) {
        lots.push({ date: o.date, units: o.units, nav: o.nav });
        continue;
      }
      let toSell = -o.units;
      while (toSell > 1e-9 && lots.length) {
        const lot = lots[0];
        const u = Math.min(lot.units, toSell);
        const gain = u * (o.nav - lot.nav);
        if (o.date >= start && o.date <= end) {
          if (o.date - lot.date > 365 * DAY) out.realisedLongTerm += gain;
          else out.realisedShortTerm += gain;
        }
        lot.units -= u;
        toSell -= u;
        if (lot.units <= 1e-9) lots.shift();
      }
    }
    for (const lot of lots) {
      const gain = lot.units * (h.lastNav - lot.nav);
      const age = now - lot.date;
      if (age > 365 * DAY) out.unrealisedLongTerm += gain;
      else {
        out.unrealisedShortTerm += gain;
        if (gain > 0 && 365 * DAY - age <= 60 * DAY) out.maturingSoon.push({ scheme: h.scheme, date: lot.date + 366 * DAY, gain });
      }
    }
  }
  out.harvestable = Math.max(0, Math.min(LTCG_EXEMPTION - Math.max(0, out.realisedLongTerm), out.unrealisedLongTerm));
  out.maturingSoon.sort((a, b) => a.date - b.date);
  return out;
}
