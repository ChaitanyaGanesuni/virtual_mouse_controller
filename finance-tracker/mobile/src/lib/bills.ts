import { inr } from './analysis';
import type { BillNotice, Ledger } from './ledger';
import type { PlannedReminder } from './reminders';
import type { BillKind } from './smsParser';
import type { Account, Transaction } from './types';

const DAY = 86_400_000;

export type BillState = 'due' | 'overdue' | 'paid';

export interface BillView extends BillNotice {
  state: BillState;
  paidOn: number | null;
}

const token = (s: string) => s.toLowerCase().replace(/[^a-z]/g, '').slice(0, 5);

/** Latest notice per biller, marked paid when a matching payment (similar amount, mentions the biller) follows it. */
export function billViews(bills: BillNotice[], txns: Transaction[], now = Date.now()): BillView[] {
  const latest = new Map<string, BillNotice>();
  for (const b of bills) latest.set(b.biller, b); // bills are oldest first
  const views: BillView[] = [];
  for (const b of latest.values()) {
    const t = token(b.biller);
    const pay = txns.find(
      (x) =>
        x.direction === 'debit' &&
        x.date >= b.date - 3 * DAY &&
        x.amount >= b.amount * 0.98 &&
        x.amount <= b.amount * 1.05 &&
        (token(x.merchant + x.body).length === 0 ? false : (x.merchant + ' ' + x.body).toLowerCase().replace(/[^a-z]/g, '').includes(t)),
    );
    const due = b.dueDate ?? b.date + 15 * DAY;
    const state: BillState = pay ? 'paid' : due < now - DAY ? 'overdue' : 'due';
    // Old paid bills aren't interesting; old unpaid ones stay visible for 30 days.
    if (state === 'paid' && (pay!.date < now - 20 * DAY)) continue;
    if (state === 'overdue' && due < now - 30 * DAY) continue;
    views.push({ ...b, state, paidOn: pay?.date ?? null });
  }
  const order = { overdue: 0, due: 1, paid: 2 };
  return views.sort((a, b) => order[a.state] - order[b.state] || (a.dueDate ?? 0) - (b.dueDate ?? 0));
}

export interface ExpiryView {
  service: string;
  expiresOn: number;
  daysLeft: number;
}

/** Latest expiry notice per prepaid service that hasn't already passed by more than a day. */
export function expiryViews(expiries: Ledger['expiries'], now = Date.now()): ExpiryView[] {
  const latest = new Map<string, Ledger['expiries'][number]>();
  for (const e of expiries) {
    const prev = latest.get(e.service);
    if (!prev || e.expiresOn >= prev.expiresOn) latest.set(e.service, e);
  }
  return [...latest.values()]
    .filter((e) => e.expiresOn >= now - DAY)
    .map((e) => ({ service: e.service, expiresOn: e.expiresOn, daysLeft: Math.ceil((e.expiresOn - now) / DAY) }))
    .sort((a, b) => a.expiresOn - b.expiresOn);
}

export const FASTAG_LOW = 200;

export function lowFastags(accounts: Account[]): Account[] {
  return accounts.filter((a) => a.kind === 'wallet' && a.balance != null && a.balance < FASTAG_LOW);
}

export const BILL_ICON: Record<BillKind, 'bolt' | 'fuel' | 'droplet' | 'send' | 'film' | 'shield' | 'dots'> = {
  electricity: 'bolt',
  gas: 'fuel',
  water: 'droplet',
  'phone & internet': 'send',
  tv: 'film',
  insurance: 'shield',
  other: 'dots',
};

const at = (day: number, hour: number) => {
  const d = new Date(day);
  d.setHours(hour, 0, 0, 0);
  return d.getTime();
};
const fmt = (t: number) => new Date(t).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });

/** Reminders 2 days before and on the day, for unpaid bills and expiring prepaid plans. */
export function planBillReminders(bills: BillView[], expiries: ExpiryView[], now = Date.now()): PlannedReminder[] {
  const out: PlannedReminder[] = [];
  for (const b of bills) {
    if (b.state === 'paid' || !b.dueDate) continue;
    const what = b.kind === 'insurance' ? `${b.biller} premium` : `${b.biller} bill`;
    for (const [days, hour] of [[2, 10], [0, 9]] as const) {
      const t = at(b.dueDate - days * DAY, hour);
      if (t > now) {
        out.push({
          at: t,
          title: days ? `${what}: ${inr(b.amount)} due ${fmt(b.dueDate)}` : `${what} due today: ${inr(b.amount)}`,
          text: b.kind === 'insurance' ? 'Pay on time so the policy doesn\'t lapse.' : 'Pay on time to avoid late fees or disconnection.',
        });
      }
    }
  }
  for (const e of expiries) {
    for (const [days, hour] of [[2, 10], [0, 9]] as const) {
      const t = at(e.expiresOn - days * DAY, hour);
      if (t > now) {
        out.push({
          at: t,
          title: days ? `${e.service} plan expires ${fmt(e.expiresOn)}` : `${e.service} plan expires today`,
          text: 'Recharge in time to keep your number and data running.',
        });
      }
    }
  }
  return out;
}
