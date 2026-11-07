import { categorize, type UserRule } from './categorizer';
import { parseSms } from './smsParser';
import type { Account, MfOrder, RawSms, Transaction } from './types';

export interface Ledger {
  transactions: Transaction[]; // newest first
  accounts: Account[];
  mfOrders: MfOrder[]; // oldest first
}

const DAY = 86_400_000;

/** Turns raw SMS into transactions, accounts (with latest balances) and MF orders. */
export function buildLedger(
  messages: RawSms[],
  userRules: UserRule[] = [],
  overrides: Record<string, string> = {},
): Ledger {
  const sorted = [...messages].sort((a, b) => a.date - b.date); // oldest first
  const accounts = new Map<string, Account>();
  const txns: Transaction[] = [];
  const mfOrders: MfOrder[] = [];
  const seen = new Set<string>();

  const account = (institution: string, kind: Account['kind'], last4: string): Account => {
    const key = `${institution}|${kind}|${last4 || '????'}`;
    let a = accounts.get(key);
    if (!a) {
      a = { key, institution, kind, last4, balance: null, availableLimit: null, asOf: null };
      accounts.set(key, a);
    }
    return a;
  };

  for (const sms of sorted) {
    const p = parseSms(sms);
    if (!p) continue;

    if (p.type === 'mf') {
      mfOrders.push({ id: sms.id, date: sms.date, ...p.order });
      continue;
    }
    if (p.type === 'card_due') {
      const a = account(p.institution, 'credit_card', p.last4);
      a.balance = p.amountDue;
      a.asOf = sms.date;
      continue;
    }
    if (p.type === 'balance') {
      const a = account(p.institution, 'bank', p.last4);
      a.balance = p.balance;
      a.asOf = sms.date;
      continue;
    }

    // Banks sometimes send the same alert twice; drop exact duplicates within 10 minutes.
    const dupKey = `${p.institution}|${p.last4}|${p.direction}|${p.amount}|${Math.floor(sms.date / 600_000)}`;
    if (seen.has(dupKey)) continue;
    seen.add(dupKey);

    const a = account(p.institution, p.accountKind, p.last4);
    if (p.balance != null) {
      a.balance = p.balance;
      a.asOf = sms.date;
    }
    if (p.availableLimit != null) {
      a.availableLimit = p.availableLimit;
      a.asOf = sms.date;
    }

    txns.push({
      id: sms.id,
      date: sms.date,
      amount: p.amount,
      direction: p.direction,
      accountKey: a.key,
      institution: p.institution,
      accountKind: p.accountKind,
      last4: p.last4,
      merchant: p.merchant,
      mode: p.mode,
      category: categorize(p.merchant, sms.body, p.direction, p.mode, userRules),
      body: sms.body,
    });
  }

  pairInternalMoves(txns);

  for (const t of txns) if (overrides[t.id]) t.category = overrides[t.id];

  return {
    transactions: txns.sort((x, y) => y.date - x.date),
    accounts: [...accounts.values()].sort((x, y) => x.kind.localeCompare(y.kind) || x.institution.localeCompare(y.institution)),
    mfOrders,
  };
}

/**
 * A debit in one of your accounts matched by an equal credit in another within 2 days is
 * money moving between your own pots (self transfer, or paying your credit-card bill),
 * not spending or income.
 */
function pairInternalMoves(txns: Transaction[]): void {
  const used = new Set<string>();
  const credits = txns.filter((t) => t.direction === 'credit' && !['Salary', 'Refund', 'Interest & Dividends'].includes(t.category));
  for (const d of txns) {
    if (d.direction !== 'debit' || ['Fees & Charges', 'Cash Withdrawal'].includes(d.category)) continue;
    const match = credits.find(
      (c) => !used.has(c.id) && c.accountKey !== d.accountKey && c.amount === d.amount && Math.abs(c.date - d.date) <= 2 * DAY,
    );
    if (!match) continue;
    used.add(match.id);
    const cat = match.accountKind === 'credit_card' ? 'Card Bill Payment' : 'Self Transfer';
    d.category = cat;
    match.category = cat;
  }
}
