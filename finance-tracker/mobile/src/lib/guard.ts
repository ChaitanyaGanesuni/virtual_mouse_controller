import { isSpend } from './analysis';
import type { FailedDebit } from './ledger';
import { helplineFrom } from './smsParser';
import type { Transaction } from './types';

const DAY = 86_400_000;
const MIN = 60_000;

// ---------------------------------------------------------------- failed payments

export type FailedStatus = 'refunded' | 'waiting' | 'overdue';

export interface FailedPayment extends FailedDebit {
  status: FailedStatus;
  /** When the bank must have reversed it by (RBI turnaround time, with a weekend buffer). */
  dueBy: number;
  refundedAt: number | null;
  /** RBI's ₹100/day compensation for each day past the deadline (estimate). */
  compensation: number;
  helpline: string | null;
  rule: string;
}

/**
 * RBI's harmonised turnaround times (2019): UPI/IMPS failures must be auto-reversed by T+1 working day;
 * card, ATM and other failures by T+5. After that the bank owes ₹100 per day. Calendar-day buffers are
 * used here because bank holidays aren't known on the phone.
 */
function deadline(f: FailedDebit): { dueBy: number; rule: string } {
  const fast = f.mode === 'UPI' || f.mode === 'IMPS';
  return fast
    ? { dueBy: f.date + 2 * DAY, rule: 'UPI/IMPS: reversal due by the next working day (T+1)' }
    : { dueBy: f.date + 7 * DAY, rule: f.mode === 'ATM' ? 'ATM cash not dispensed: reversal due within 5 working days (T+5)' : 'Card/other: reversal due within 5 working days (T+5)' };
}

const REFUND_RE = /revers|refund|failed|declined|credited back/i;

export function trackFailedPayments(failed: FailedDebit[], txns: Transaction[], now = Date.now()): FailedPayment[] {
  const used = new Set<string>();
  return [...failed]
    .sort((a, b) => b.date - a.date)
    .map((f) => {
      const { dueBy, rule } = deadline(f);
      const refund = txns
        .filter(
          (t) =>
            t.direction === 'credit' &&
            !used.has(t.id) &&
            t.institution === f.institution &&
            (!f.last4 || !t.last4 || t.last4 === f.last4) &&
            Math.abs(t.amount - f.amount) < 0.01 &&
            t.date >= f.date &&
            t.date - f.date <= 45 * DAY &&
            (REFUND_RE.test(t.body) || t.category === 'Refund' || t.category === 'Reversed'),
        )
        .sort((a, b) => a.date - b.date)[0];
      if (refund) used.add(refund.id);
      const end = refund ? refund.date : now;
      const lateDays = Math.max(0, Math.floor((end - dueBy) / DAY));
      const status: FailedStatus = refund ? 'refunded' : now > dueBy ? 'overdue' : 'waiting';
      return {
        ...f,
        status,
        dueBy,
        refundedAt: refund?.date ?? null,
        compensation: lateDays * 100,
        helpline: helplineFrom(f.body),
        rule,
      };
    });
}

// ---------------------------------------------------------------- fraud / unusual activity

export type SignalKind = 'duplicate' | 'new-merchant' | 'foreign' | 'odd-hour';

export interface Signal {
  id: string; // stable, so a dismissed signal stays dismissed
  kind: SignalKind;
  title: string;
  detail: string;
  date: number;
  amount: number;
  txnIds: string[];
  helpline: string | null;
}

const FOREIGN_RE = /\b(USD|EUR|GBP|AED|SGD|AUD|CAD|JPY|CHF)\b|international|\bintl\.?\b|foreign currency|forex|cross[- ]border/i;
const EXPECTED = new Set(['Rent & Housing', 'EMI & Loans', 'Insurance', 'Education', 'Investments', 'Self Transfer', 'Card Bill Payment', 'Reversed']);
const norm = (m: string) => m.toLowerCase().replace(/[^a-z]/g, '');

export function findSignals(txns: Transaction[], now = Date.now(), windowDays = 30): Signal[] {
  const out: Signal[] = [];
  const debits = txns.filter((t) => t.direction === 'debit').sort((a, b) => a.date - b.date);
  const recent = debits.filter((t) => t.date >= now - windowDays * DAY);
  const typical = debits.filter((t) => isSpend(t) && t.date >= now - 90 * DAY).map((t) => t.amount).sort((a, b) => a - b);
  const median = typical.length ? typical[Math.floor(typical.length / 2)] : 0;

  // Same merchant + amount on the same account within 15 minutes, as separate messages.
  for (let i = 0; i < recent.length; i++) {
    for (let j = i + 1; j < recent.length && recent[j].date - recent[i].date <= 15 * MIN; j++) {
      const a = recent[i];
      const b = recent[j];
      if (a.accountKey === b.accountKey && a.merchant && norm(a.merchant) === norm(b.merchant) && Math.abs(a.amount - b.amount) < 0.01) {
        out.push({
          id: `dup|${a.key}|${b.key}`,
          kind: 'duplicate',
          title: `Charged twice? ${a.merchant}`,
          detail: `Two payments of ₹${a.amount.toLocaleString('en-IN')} to ${a.merchant} ${Math.round((b.date - a.date) / MIN)} min apart. If you paid once, ask the merchant for a refund, or raise a dispute with your bank.`,
          date: b.date,
          amount: b.amount,
          txnIds: [a.id, b.id],
          helpline: helplineFrom(b.body),
        });
      }
    }
  }

  for (const t of recent) {
    if (!isSpend(t) && t.category !== 'Fees & Charges') continue;
    if (EXPECTED.has(t.category)) continue;

    if (FOREIGN_RE.test(t.body)) {
      out.push({
        id: `foreign|${t.key}`,
        kind: 'foreign',
        title: `International charge: ${t.merchant || t.institution}`,
        detail: 'A foreign-currency or international payment on your card. If this wasn\'t you, block the card right away and report it.',
        date: t.date,
        amount: t.amount,
        txnIds: [t.id],
        helpline: helplineFrom(t.body),
      });
      continue;
    }

    const hour = new Date(t.date).getHours();
    if (hour < 5 && t.amount >= 2000 && (t.mode === 'CARD' || t.accountKind === 'credit_card')) {
      out.push({
        id: `night|${t.key}`,
        kind: 'odd-hour',
        title: `Late-night card payment: ₹${t.amount.toLocaleString('en-IN')}`,
        detail: `At ${new Date(t.date).toLocaleTimeString('en-IN', { hour: 'numeric', minute: '2-digit' })} to ${t.merchant || 'an unknown merchant'}. Was it you?`,
        date: t.date,
        amount: t.amount,
        txnIds: [t.id],
        helpline: helplineFrom(t.body),
      });
      continue;
    }

    if (t.merchant && t.amount >= Math.max(5000, median * 4)) {
      const seenBefore = debits.some((o) => o.date < t.date && norm(o.merchant) === norm(t.merchant));
      if (!seenBefore) {
        out.push({
          id: `new|${t.key}`,
          kind: 'new-merchant',
          title: `First payment to ${t.merchant}: ₹${t.amount.toLocaleString('en-IN')}`,
          detail: `A large payment to someone you haven't paid before (about ${Math.round(t.amount / Math.max(median, 1))}× your typical payment). Fine if you expected it.`,
          date: t.date,
          amount: t.amount,
          txnIds: [t.id],
          helpline: helplineFrom(t.body),
        });
      }
    }
  }
  return out.sort((a, b) => b.date - a.date);
}

/** National cybercrime helpline (India) for reporting online financial fraud quickly. */
export const CYBERCRIME_HELPLINE = '1930';
