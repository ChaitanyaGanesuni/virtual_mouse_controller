import { categorize, type UserRule } from './categorizer';
import { looksLikeTransactionAlert, parseSms } from './smsParser';
import type { Account, MfOrder, RawSms, Transaction } from './types';

export interface Ledger {
  transactions: Transaction[]; // newest first
  accounts: Account[];
  mfOrders: MfOrder[]; // oldest first
  /** Bank/card alerts that look like transactions but could not be parsed. Newest first. */
  missed: RawSms[];
}

const DAY = 86_400_000;
const MIN = 60_000;

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
  const missed: RawSms[] = [];
  const seen = new Set<string>();

  const account = (institution: string, kind: Account['kind'], last4: string): Account => {
    const key = `${institution}|${kind}|${last4 || '????'}`;
    let a = accounts.get(key);
    if (!a) {
      a = {
        key,
        institution,
        kind,
        last4,
        balance: null,
        availableLimit: null,
        asOf: null,
        statementDue: null,
        statementDate: null,
        minDue: null,
        dueDate: null,
        paidSinceStatement: 0,
      };
      accounts.set(key, a);
    }
    return a;
  };

  for (const sms of sorted) {
    const p = parseSms(sms);
    if (!p) {
      if (looksLikeTransactionAlert(sms)) missed.push(sms);
      continue;
    }

    if (p.type === 'mf') {
      mfOrders.push({ id: sms.id, date: sms.date, ...p.order });
      continue;
    }
    if (p.type === 'card_due') {
      const a = account(p.institution, 'credit_card', p.last4);
      a.statementDue = p.amountDue;
      a.statementDate = sms.date;
      a.minDue = p.minDue;
      a.dueDate = p.dueDate;
      a.paidSinceStatement = 0;
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
    // Payments and refunds credited to a card after its statement reduce what is still due.
    if (a.kind === 'credit_card' && p.direction === 'credit' && a.statementDate != null) {
      a.paidSinceStatement += p.amount;
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

  for (const a of accounts.values()) {
    if (a.kind === 'credit_card' && a.statementDue != null) {
      a.balance = Math.max(0, Math.round((a.statementDue - a.paidSinceStatement) * 100) / 100);
    }
  }

  pairInternalMoves(txns, [...accounts.values()]);

  for (const t of txns) if (overrides[t.id]) t.category = overrides[t.id];

  return {
    transactions: txns.sort((x, y) => y.date - x.date),
    accounts: [...accounts.values()].sort((x, y) => x.kind.localeCompare(y.kind) || x.institution.localeCompare(y.institution)),
    mfOrders,
    missed: missed.reverse(),
  };
}

const CARD_PAY_RE = /credit card|\bcc\b|card ?(?:bill|payment|dues?)|\bcred\b|billdesk|bbps|towards your card/i;
const SELF_RE = /\bself\b|own account|to your (?:other )?a\/c|between your accounts/i;

/**
 * Finds money that only moved between your own accounts, so it is not counted as spending or income:
 *  - card bill payments: a bank debit and an equal credit on one of your cards within 3 days, where
 *    the debit mentions a card / bill payment or the card alert says a payment was received;
 *  - self transfers: an equal debit and credit in two of your bank accounts that either name each
 *    other (account last digits, "self") or arrive within 30 minutes of each other.
 * A payment to a friend followed later by an unrelated credit of the same amount is not paired.
 */
function pairInternalMoves(txns: Transaction[], accounts: Account[]): void {
  const used = new Set<string>();
  const myLast4 = new Set(accounts.map((a) => a.last4).filter((x) => x.length >= 3));
  const skipDebit = new Set(['Fees & Charges', 'Cash Withdrawal', 'Investments']);
  const skipCredit = new Set(['Salary', 'Refund', 'Interest & Dividends', 'Investments']);

  const mentionsOther = (body: string, ownLast4: string) =>
    [...myLast4].some((l4) => l4 !== ownLast4 && new RegExp(`(?:x|\\*|\\.|\\s)${l4}\\b`, 'i').test(body));

  for (const d of txns) {
    if (d.direction !== 'debit' || d.accountKind !== 'bank' || skipDebit.has(d.category)) continue;
    const candidates = txns.filter(
      (c) =>
        c.direction === 'credit' &&
        !used.has(c.id) &&
        c.accountKey !== d.accountKey &&
        !skipCredit.has(c.category) &&
        Math.abs(c.amount - d.amount) < 0.01,
    );
    let match: Transaction | undefined;
    let cat = '';

    match = candidates.find(
      (c) =>
        c.accountKind === 'credit_card' &&
        Math.abs(c.date - d.date) <= 3 * DAY &&
        (CARD_PAY_RE.test(d.body) || c.category === 'Card Bill Payment'),
    );
    if (match) cat = 'Card Bill Payment';

    if (!match) {
      match = candidates.find(
        (c) =>
          c.accountKind === 'bank' &&
          Math.abs(c.date - d.date) <= DAY &&
          (SELF_RE.test(d.body) ||
            SELF_RE.test(c.body) ||
            mentionsOther(d.body, d.last4) ||
            mentionsOther(c.body, c.last4) ||
            Math.abs(c.date - d.date) <= 30 * MIN),
      );
      if (match) cat = 'Self Transfer';
    }
    if (!match) continue;
    used.add(match.id);
    d.category = cat;
    match.category = cat;
  }
}
