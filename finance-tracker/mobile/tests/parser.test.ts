import assert from 'node:assert/strict';
import { test } from 'node:test';

import { byCategory, findRecurring, wasteInsights } from '../src/lib/analysis';
import { demoMessages } from '../src/lib/demo';
import { buildHoldings, investmentInsights, xirr } from '../src/lib/investments';
import { buildLedger } from '../src/lib/ledger';
import { parseSms } from '../src/lib/smsParser';

const sms = (address: string, body: string) => ({ id: '1', address, body, date: Date.now() });

test('HDFC UPI debit', () => {
  const p = parseSms(sms('AX-HDFCBK', 'Sent Rs.250.00 From HDFC Bank A/C *1234 To swiggy@icici On 05-11-26 Ref 123456 Not You? Avl Bal Rs.10,500.50'));
  assert.ok(p && p.type === 'txn');
  assert.equal(p.amount, 250);
  assert.equal(p.direction, 'debit');
  assert.equal(p.institution, 'HDFC Bank');
  assert.equal(p.last4, '1234');
  assert.equal(p.merchant, 'swiggy');
  assert.equal(p.mode, 'UPI');
  assert.equal(p.balance, 10500.5);
});

test('SBI UPI debit without currency symbol', () => {
  const p = parseSms(sms('VM-SBIINB', 'Dear UPI user A/C X5678 debited by 520.0 on date 05Nov26 trf to ZOMATO LTD Refno 431234567890. If not u? call 1800111109. -SBI'));
  assert.ok(p && p.type === 'txn');
  assert.equal(p.amount, 520);
  assert.equal(p.direction, 'debit');
  assert.equal(p.institution, 'SBI');
  assert.equal(p.merchant, 'ZOMATO LTD');
});

test('ICICI debit with merchant credited', () => {
  const p = parseSms(sms('JD-ICICIB-S', 'ICICI Bank Acct XX321 debited for Rs 1,499.00 on 05-Nov-26; AMAZON PAY credited. UPI:431234. Call 18002662 for dispute.'));
  assert.ok(p && p.type === 'txn');
  assert.equal(p.direction, 'debit');
  assert.equal(p.amount, 1499);
  assert.equal(p.merchant, 'AMAZON PAY');
});

test('credit card spend', () => {
  const p = parseSms(sms('JD-ICICIT', 'INR 649.00 spent using ICICI Bank Card XX9034 on 06-11-26 on NETFLIX.COM. Avl Limit: INR 1,20,000.00.'));
  assert.ok(p && p.type === 'txn');
  assert.equal(p.accountKind, 'credit_card');
  assert.equal(p.merchant, 'NETFLIX.COM');
  assert.equal(p.availableLimit, 120000);
});

test('salary credit', () => {
  const p = parseSms(sms('VM-HDFCBK', 'Your A/c XX4821 is credited with INR 1,45,000.00 on 01-11-26 by NEFT-SALARY ACME TECHNOLOGIES. Avl Bal INR 2,00,000.00'));
  assert.ok(p && p.type === 'txn');
  assert.equal(p.direction, 'credit');
  assert.equal(p.amount, 145000);
});

test('ignores OTP, offers, personal senders', () => {
  assert.equal(parseSms(sms('AX-HDFCBK', 'OTP for txn of Rs.4,999.00 at AMAZON is 482913.')), null);
  assert.equal(parseSms(sms('AX-HDFCBK', 'Pre-approved personal loan of Rs.5,00,000 ready! Apply now.')), null);
  assert.equal(parseSms(sms('+919812345678', 'Rs 500 debited lol')), null);
});

test('mutual fund allotment', () => {
  const p = parseSms(sms('VM-CAMSPL', 'Dear Investor, your SIP purchase of Rs.5,000.00 in Folio 7781234/56 under Axis Bluechip Fund - Regular Growth is processed at NAV of 52.1000 for 95.969 units.'));
  assert.ok(p && p.type === 'mf');
  assert.equal(p.order.scheme, 'Axis Bluechip Fund - Regular Growth');
  assert.equal(p.order.units, 95.969);
  assert.equal(p.order.folio, '7781234/56');
});

test('xirr of 10% a year', () => {
  const t0 = Date.UTC(2024, 0, 1);
  const r = xirr([
    { date: t0, amount: -1000 },
    { date: t0 + 365 * 86_400_000, amount: 1100 },
  ]);
  assert.ok(r != null && Math.abs(r - 0.1) < 1e-4);
});

test('demo data end-to-end', () => {
  const now = Date.now();
  const ledger = buildLedger(demoMessages(now));
  assert.ok(ledger.transactions.length > 100);
  const cats = byCategory(ledger.transactions).map((c) => c.category);
  for (const c of ['Rent & Housing', 'Food Delivery', 'Subscriptions', 'Cabs', 'Groceries']) assert.ok(cats.includes(c), `missing ${c}: ${cats}`);
  // card bill payments are not double counted as spend
  assert.ok(!cats.includes('Card Bill Payment'));
  assert.ok(ledger.transactions.some((t) => t.category === 'Card Bill Payment' && t.direction === 'credit'));

  const rec = findRecurring(ledger.transactions, now).map((r) => r.merchant);
  assert.ok(rec.some((m) => /netflix/i.test(m)), `recurring: ${rec}`);

  const ids = wasteInsights(ledger.transactions, now).map((i) => i.id);
  for (const id of ['fees', 'subscriptions', 'food-delivery', 'betting']) assert.ok(ids.includes(id), `insights: ${ids}`);

  const holdings = buildHoldings(ledger.mfOrders);
  assert.equal(holdings.length, 2);
  assert.ok(holdings.some((h) => h.plan === 'regular'));
  const inv = investmentInsights(holdings, ledger.accounts, ledger.transactions, undefined, now).map((i) => i.id);
  assert.ok(inv.includes('regular-plans'), `inv: ${inv}`);

  const bank = ledger.accounts.find((a) => a.kind === 'bank' && a.last4 === '4821');
  assert.ok(bank && bank.balance != null);
});

test('KFin allotment scheme name', () => {
  const p = parseSms(sms('VM-KFINTK', 'Dear Investor, your purchase of Rs.5,000.00 in Folio 91234567 under Parag Parikh Flexi Cap Fund - Direct Growth is processed at NAV of 78.1000 for 64.020 units.'));
  assert.ok(p && p.type === 'mf');
  assert.equal(p.order.scheme, 'Parag Parikh Flexi Cap Fund - Direct Growth');
});

import { parseDateText } from '../src/lib/dates';
import { maskSms } from '../src/lib/smsParser';

const at = (id: string, address: string, body: string, date: number) => ({ id, address, body, date });

test('date formats', () => {
  const ref = new Date(2026, 10, 8).getTime();
  const ymd = (t: number | null) => (t == null ? null : new Date(t).toISOString().slice(0, 10));
  assert.equal(ymd(parseDateText('28-11-26', ref)), '2026-11-28');
  assert.equal(ymd(parseDateText('28/11/2026', ref)), '2026-11-28');
  assert.equal(ymd(parseDateText('28-Nov-26', ref)), '2026-11-28');
  assert.equal(ymd(parseDateText('28 November 2026', ref)), '2026-11-28');
  assert.equal(ymd(parseDateText('05Dec26', ref)), '2026-12-05');
  assert.equal(ymd(parseDateText('Dec 5, 2026', ref)), '2026-12-05');
  assert.equal(ymd(parseDateText('05 Jan', ref)), '2027-01-05');
});

test('card statement: due date, min due, and dues drop after payment', () => {
  const t0 = new Date(2026, 10, 1).getTime();
  const msgs = [
    at('1', 'JD-ICICIT', 'ICICI Bank Credit Card XX9034 statement: Total Amt Due Rs 20,000.00. Min Amt Due Rs 1,000.00. Pay by 21-11-26.', t0),
    at('2', 'JD-ICICIT', 'Dear Customer, Payment of INR 15,000.00 has been received on your ICICI Bank Credit Card Account XX9034. Thank you.', t0 + 5 * 86_400_000),
  ];
  const card = buildLedger(msgs).accounts.find((a) => a.kind === 'credit_card')!;
  assert.equal(card.statementDue, 20000);
  assert.equal(card.minDue, 1000);
  assert.equal(new Date(card.dueDate!).getDate(), 21);
  assert.equal(card.balance, 5000);
});

test('friend payment is not mistaken for a self transfer', () => {
  const t0 = new Date(2026, 10, 1, 10).getTime();
  const msgs = [
    at('1', 'AX-HDFCBK', 'Sent Rs.500.00 From HDFC Bank A/C *4821 To rahul@okaxis On 01-11-26 Ref 123456789012. Avl Bal Rs.9,500.00', t0),
    at('2', 'VM-SBIINB', 'Your A/c X5678 is credited by Rs.500.00 on 01Nov26 by UPI from PRIYA S Ref 987654321098', t0 + 8 * 3_600_000),
  ];
  const l = buildLedger(msgs);
  assert.ok(l.transactions.every((t) => t.category !== 'Self Transfer'), l.transactions.map((t) => t.category).join());
});

test('self transfer between own accounts is paired', () => {
  const t0 = new Date(2026, 10, 1, 10).getTime();
  const msgs = [
    at('1', 'AX-HDFCBK', 'Rs.20,000.00 debited from A/c XX4821 on 01-11-26 by IMPS to A/c XX5678 Ref 123456789012. Avl Bal Rs.9,500.00', t0),
    at('2', 'VM-SBIINB', 'Your A/c X5678 is credited by Rs.20,000.00 on 01Nov26 by IMPS Ref 123456789012', t0 + 3 * 3_600_000),
  ];
  const l = buildLedger(msgs);
  assert.deepEqual(l.transactions.map((t) => t.category), ['Self Transfer', 'Self Transfer']);
});

test('unreadable bank alerts are listed as missed, promos are not', () => {
  const t0 = Date.now();
  const msgs = [
    at('1', 'VM-XYZBNK', 'Txn of INR 1,234 done via Kotak Card ending 1122 at IKEA', t0),
    at('2', 'VM-HDFCBK', 'Get flat 10% off up to Rs 1,500 on your HDFC Bank Credit Card at Myntra!', t0),
  ];
  const l = buildLedger(msgs);
  // first is either parsed or reported as missed, never silently dropped
  assert.ok(l.transactions.length === 1 || l.missed.some((m) => m.id === '1'));
  assert.ok(!l.missed.some((m) => m.id === '2'));
  assert.equal(maskSms('Ref 123456789012 A/c 4821'), 'Ref XXXXXXXXXX12 A/c 4821');
});

import { planReminders } from '../src/lib/reminders';

test('bill reminders: 3 days before, day before, due day; none once paid', () => {
  const now = new Date(2026, 10, 10, 8).getTime();
  const card = {
    key: 'k', institution: 'ICICI Bank', kind: 'credit_card' as const, last4: '9034', balance: 5000,
    availableLimit: null, asOf: null, statementDue: 20000, statementDate: now, minDue: 1000,
    dueDate: new Date(2026, 10, 21, 12).getTime(), paidSinceStatement: 15000,
  };
  const r = planReminders([card], now);
  assert.deepEqual(r.map((x) => new Date(x.at).getDate()), [18, 20, 21]);
  assert.match(r[0].title, /₹5,000 due on 21 Nov/);
  assert.equal(planReminders([{ ...card, balance: 0 }], now).length, 0);
});
