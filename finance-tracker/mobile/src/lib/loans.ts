import type { Ledger } from './ledger';
import type { Transaction } from './types';

const DAY = 86_400_000;
const MONTH = 30.44 * DAY;

export type LoanType = 'home' | 'car' | 'personal' | 'education' | 'gold' | 'consumer' | 'other';

/** Typical rates in India (late 2026) used until you set your own. */
export const DEFAULT_RATE: Record<LoanType, number> = {
  home: 0.085,
  car: 0.095,
  personal: 0.13,
  education: 0.1,
  gold: 0.1,
  consumer: 0.16,
  other: 0.12,
};

export interface LoanSettings {
  rate?: number; // annual, e.g. 0.085
  outstanding?: number; // as of `asOf`
  asOf?: number;
}

export interface Loan {
  id: string;
  name: string;
  type: LoanType;
  emi: number;
  emisPaid: number;
  firstEmi: number;
  lastEmi: number;
  rate: number;
  rateIsDefault: boolean;
  /** Outstanding today, if known (from lender SMS or your own entry), rolled forward by EMIs since. */
  outstanding: number | null;
  outstandingSource: 'sms' | 'you' | null;
  monthsLeft: number | null;
  interestLeft: number | null;
  payoffDate: number | null;
}

/** Months to repay `p` at monthly rate `r` with instalment `e` (Infinity if the EMI doesn't cover interest). */
export function monthsToRepay(p: number, r: number, e: number): number {
  if (p <= 0) return 0;
  if (r === 0) return p / e;
  if (e <= p * r) return Infinity;
  return -Math.log(1 - (r * p) / e) / Math.log(1 + r);
}

/** Paying `x` extra now, keeping the same EMI: interest saved and months saved. */
export function prepayImpact(p: number, annualRate: number, e: number, x: number) {
  const r = annualRate / 12;
  const n = monthsToRepay(p, r, e);
  const p2 = Math.max(0, p - x);
  const n2 = monthsToRepay(p2, r, e);
  const interest = (months: number, principal: number) => Math.max(0, months * e - principal);
  return {
    monthsSaved: Number.isFinite(n) ? n - n2 : 0,
    interestSaved: Number.isFinite(n) ? interest(n, p) - interest(n2, p2) : 0,
    newMonths: n2,
  };
}

function loanType(text: string): LoanType {
  const t = text.toLowerCase();
  if (/home|housing|mortgage|lap\b/.test(t)) return 'home';
  if (/car|auto|vehicle|two ?wheeler|bike/.test(t)) return 'car';
  if (/education|student/.test(t)) return 'education';
  if (/gold/.test(t)) return 'gold';
  if (/bajaj|consumer|durable|no cost emi|home ?credit|zestmoney/.test(t)) return 'consumer';
  if (/personal|pl\b|instant loan/.test(t)) return 'personal';
  return 'other';
}

const LOAN_NO_RE = /loan\s*(?:a\/c|acct|account|no\.?)\s*(?:no\.?)?\s*[:\s]*[x*.\s]*(\d{3,})/i;

/** Groups EMI debits into loans and works out what's left. */
export function detectLoans(txns: Transaction[], points: Ledger['loanPoints'], settings: Record<string, LoanSettings>, now = Date.now()): Loan[] {
  const emis = txns.filter((t) => t.direction === 'debit' && t.category === 'EMI & Loans').sort((a, b) => a.date - b.date);
  const groups = new Map<string, Transaction[]>();
  for (const t of emis) {
    const no = LOAN_NO_RE.exec(t.body)?.[1]?.slice(-4);
    const id = no ? `${t.institution}|${no}` : (t.merchant || t.institution).toLowerCase().replace(/[^a-z0-9]/g, '');
    groups.set(id, [...(groups.get(id) ?? []), t]);
  }
  const loans: Loan[] = [];
  for (const [id, list] of groups) {
    if (list.length < 2) continue; // one-off payments aren't a running loan
    const recent = list.slice(-6).map((t) => t.amount).sort((a, b) => a - b);
    const emi = recent[Math.floor(recent.length / 2)];
    const type = loanType(list.map((t) => t.body + ' ' + t.merchant).join(' '));
    const s = settings[id] ?? {};
    const rate = s.rate ?? DEFAULT_RATE[type];
    const r = rate / 12;
    const last4 = id.includes('|') ? id.split('|')[1] : '';
    const point = [...points].reverse().find((p) => (last4 && p.last4 === last4) || (!last4 && p.lender === list[0].institution));
    let base: { amount: number; at: number; src: 'sms' | 'you' } | null = null;
    if (s.outstanding != null && s.asOf != null && (!point || s.asOf >= point.date)) base = { amount: s.outstanding, at: s.asOf, src: 'you' };
    else if (point) base = { amount: point.outstanding, at: point.date, src: 'sms' };
    let outstanding: number | null = null;
    if (base) {
      // Each EMI since then repays (EMI − interest on what's left).
      let p = base.amount;
      for (const t of list) if (t.date > base.at) p = Math.max(0, p - (t.amount - p * r));
      outstanding = p;
    }
    const n = outstanding != null ? monthsToRepay(outstanding, r, emi) : null;
    loans.push({
      id,
      name: list[list.length - 1].merchant || `${list[0].institution} loan${last4 ? ` ••${last4}` : ''}`,
      type,
      emi,
      emisPaid: list.length,
      firstEmi: list[0].date,
      lastEmi: list[list.length - 1].date,
      rate,
      rateIsDefault: s.rate == null,
      outstanding,
      outstandingSource: base?.src ?? null,
      monthsLeft: n != null && Number.isFinite(n) ? n : null,
      interestLeft: n != null && Number.isFinite(n) && outstanding != null ? Math.max(0, n * emi - outstanding) : null,
      payoffDate: n != null && Number.isFinite(n) ? now + n * MONTH : null,
    });
  }
  return loans.sort((a, b) => b.emi - a.emi);
}
