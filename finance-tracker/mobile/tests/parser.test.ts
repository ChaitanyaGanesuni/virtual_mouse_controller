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
  assert.equal(holdings.length, 3);
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

import { moneyHealth } from '../src/lib/health';

test('money health score is 0-100 and penalises fees and regular plans', () => {
  const now = Date.now();
  const l = buildLedger(demoMessages(now));
  const h = moneyHealth(l.transactions, l.accounts, buildHoldings(l.mfOrders), now)!;
  assert.ok(h.score >= 0 && h.score <= 100, String(h.score));
  assert.equal(h.parts.reduce((s, p) => s + p.max, 0), 100);
  assert.ok(h.parts.find((p) => p.key === 'fees')!.score < 20);
  assert.ok(h.parts.find((p) => p.key === 'costs')!.score < 10);
  assert.equal(moneyHealth([], [], [], now), null);
});

import { totalMonthlySaving } from '../src/lib/analysis';

test('total saving counts overlapping insights once', () => {
  const now = Date.now();
  const w = wasteInsights(buildLedger(demoMessages(now)).transactions, now);
  const naive = w.reduce((s, i) => s + (i.monthlySaving ?? 0), 0);
  const total = totalMonthlySaving(w);
  assert.ok(total > 0 && total <= naive);
  const byKey = new Map<string, number>();
  for (const i of w) byKey.set(i.savingKey ?? i.id, (byKey.get(i.savingKey ?? i.id) ?? 0) + 1);
  assert.ok([...byKey.values()].some((n) => n > 1) ? total < naive : total === naive);
  assert.equal(totalMonthlySaving([
    { id: 'a', title: '', detail: '', severity: 'low', monthlySaving: 100, savingKey: 'Dining Out' },
    { id: 'b', title: '', detail: '', severity: 'low', monthlySaving: 300, savingKey: 'Dining Out' },
    { id: 'c', title: '', detail: '', severity: 'low', monthlySaving: 50 },
  ]), 350);
});

test('health score without income leaves income parts unscored instead of zero', () => {
  const now = Date.now();
  const l = buildLedger(demoMessages(now));
  const noIncome = l.transactions.filter((t) => t.direction !== 'credit');
  const h = moneyHealth(noIncome, l.accounts, [], now)!;
  assert.ok(h.partial && /savings rate/.test(h.partial));
  assert.ok(h.parts.filter((p) => p.unknown).length === 3);
  assert.ok(h.score > 0 && h.score <= 100);
});

test('a message that breaks the parser is skipped and reported, not fatal', () => {
  const bad = { id: 'x', address: 'AX-HDFCBK', body: null as unknown as string, date: Date.now() };
  const good = { id: 'y', address: 'AX-HDFCBK', body: 'Sent Rs.250.00 From HDFC Bank A/C *1234 To swiggy@icici On 05-11-26 Ref 1. Avl Bal Rs.100', date: Date.now() };
  const l = buildLedger([bad, good]);
  assert.equal(l.failures.length, 1);
  assert.equal(l.transactions.length, 1);
});

import { budgetAlerts, budgetStatus, suggestBudgets } from '../src/lib/budgets';
import { monthForecast } from '../src/lib/forecast';
import { netWorthHistory } from '../src/lib/history';

test('budgets: suggestions, status, alerts once per threshold', () => {
  const now = Date.now();
  const l = buildLedger(demoMessages(now));
  const sug = suggestBudgets(l.transactions, now);
  assert.ok(sug['Food Delivery'] > 0 && sug['Food Delivery'] % 500 === 0, JSON.stringify(sug));
  assert.ok(!('Card Bill Payment' in sug) && !('Investments' in sug));
  const st = budgetStatus(l.transactions, { 'Rent & Housing': 30000, Groceries: 1e9 }, now);
  const rent = st.find((s) => s.category === 'Rent & Housing')!;
  const day = new Date(now).getDate();
  if (day >= 4) {
    assert.ok(rent.pct >= 1);
    const a = budgetAlerts(st, [], now);
    assert.equal(a.length, 1);
    assert.match(a[0].title, /used up/);
    assert.equal(budgetAlerts(st, [a[0].key], now).length, 0);
  }
});

test('forecast: projected >= spent so far, upcoming recurring within month', () => {
  const now = new Date(2026, 10, 8, 12).getTime();
  const f = monthForecast(buildLedger(demoMessages(now)).transactions, now);
  assert.ok(f.projectedSpend >= f.spentSoFar);
  assert.ok(f.dailyRate > 0);
  assert.equal(f.expectedIncome, 145000);
  assert.ok(f.upcoming.every((u) => u.date > now && u.date <= f.monthEnd));
  const names = f.upcoming.map((u) => u.merchant);
  assert.ok(names.some((m) => /spotify/i.test(m)), JSON.stringify(names)); // charged 9 Oct -> due 9 Nov
  assert.ok(!names.some((m) => /netflix/i.test(m))); // already charged 6 Nov
  assert.equal(new Date(f.upcoming.find((u) => /spotify/i.test(u.merchant))!.date).getDate(), 9);
});

test('net worth history: one point per month end plus today', () => {
  const now = Date.now();
  const l = buildLedger(demoMessages(now));
  const h = netWorthHistory(l, buildHoldings(l.mfOrders), 12, now);
  assert.ok(h.length >= 6 && h.length <= 12, String(h.length));
  for (let i = 1; i < h.length; i++) assert.ok(h[i].date > h[i - 1].date);
  assert.ok(h.every((p) => Number.isFinite(p.net)));
  assert.ok(h[h.length - 1].investments > h[0].investments);
});

import { findSignals, trackFailedPayments } from '../src/lib/guard';
import { helplineFrom } from '../src/lib/smsParser';

const DAYMS = 86_400_000;

test('failed payment: detected, reversal paired, status and RBI compensation', () => {
  const t0 = new Date(2026, 9, 1, 10).getTime();
  const msgs = [
    at('1', 'AX-HDFCBK', 'Rs.1,500.00 debited from A/c XX4821 for UPI txn to merchant@ybl. Txn failed. Amount will be reversed within 1 working day. Call 18002586161', t0),
    at('2', 'AX-HDFCBK', 'Rs.1,500.00 credited to A/c XX4821 as reversal of your failed UPI txn on 01-10-26.', t0 + 1 * DAYMS),
    at('3', 'AX-HDFCBK', 'Rs.800.00 debited from A/c XX4821 at ATM. Cash not dispensed. Amount will be reversed. Call 18002586161', t0 + 2 * DAYMS),
  ];
  const l = buildLedger(msgs);
  assert.equal(l.failedDebits.length, 2);
  const reversal = l.transactions.find((t) => t.id === '2')!;
  assert.ok(reversal, 'reversal credit must not be dropped as a "failed" alert');
  const now = t0 + 20 * DAYMS;
  const f = trackFailedPayments(l.failedDebits, l.transactions, now);
  const upi = f.find((x) => x.amount === 1500)!;
  const atm = f.find((x) => x.amount === 800)!;
  assert.equal(upi.status, 'refunded');
  assert.equal(atm.status, 'overdue');
  assert.equal(atm.helpline, '18002586161');
  assert.ok(atm.compensation >= 1000, String(atm.compensation));
  assert.equal(helplineFrom('If not you, call 18001080.'), '18001080');
  assert.equal(helplineFrom('Not you? Call 1800-202-6161 now'), '18002026161');
  assert.equal(helplineFrom('Ref 123456789012 done'), null);
});

test('debit followed by its reversal is not counted as spending', () => {
  const t0 = new Date(2026, 9, 1, 10).getTime();
  const l = buildLedger([
    at('1', 'AX-HDFCBK', 'Sent Rs.2,000.00 From HDFC Bank A/C *4821 To shop@ybl On 01-10-26 Ref 111111111111. Avl Bal Rs.5,000', t0),
    at('2', 'AX-HDFCBK', 'Rs.2,000.00 credited to A/c XX4821 as reversal of failed UPI txn Ref 111111111111.', t0 + DAYMS),
  ]);
  assert.deepEqual(l.transactions.map((t) => t.category), ['Reversed', 'Reversed']);
});

test('a genuine double charge is kept; an identical repeated SMS is dropped', () => {
  const t0 = new Date(2026, 9, 1, 10).getTime();
  const body = (ref: string) => `INR 999.00 spent using ICICI Bank Card XX9034 on 01-10-26 on BOOKMYSHOW. Ref ${ref}. Avl Limit: INR 50,000.00`;
  const l = buildLedger([
    at('1', 'JD-ICICIT', body('111'), t0),
    at('2', 'JD-ICICIT', body('111'), t0 + 60_000), // same SMS twice
    at('3', 'JD-ICICIT', body('222'), t0 + 120_000), // second real charge
  ]);
  assert.equal(l.transactions.length, 2);
  const s = findSignals(l.transactions, t0 + DAYMS);
  assert.ok(s.some((x) => x.kind === 'duplicate'), JSON.stringify(s.map((x) => x.kind)));
});

test('fraud signals: international and first large payment to a new merchant', () => {
  const t0 = new Date(2026, 9, 10, 14).getTime();
  const small = Array.from({ length: 10 }, (_, i) =>
    at(`s${i}`, 'AX-HDFCBK', `Sent Rs.300.00 From HDFC Bank A/C *4821 To swiggy@icici On 01-10-26 Ref ${i}. Avl Bal Rs.50,000`, t0 - (i + 1) * DAYMS),
  );
  const l = buildLedger([
    ...small,
    at('f', 'JD-ICICIT', 'INR 4,200.00 spent using ICICI Bank Card XX9034 on 10-10-26 on STEAM USD 50.00 international txn. Avl Limit: INR 40,000', t0),
    at('n', 'AX-HDFCBK', 'Sent Rs.25,000.00 From HDFC Bank A/C *4821 To quickcash@okaxis On 10-10-26 Ref 9. Avl Bal Rs.20,000', t0 + 60_000),
  ]);
  const kinds = findSignals(l.transactions, t0 + DAYMS).map((x) => x.kind);
  assert.ok(kinds.includes('foreign') && kinds.includes('new-merchant'), JSON.stringify(kinds));
});

import { capitalGains, deductions, financialYear } from '../src/lib/tax';
import { rentPayments, rentReceiptsHtml } from '../src/lib/rent';

test('financial year boundaries', () => {
  assert.equal(financialYear(new Date(2026, 2, 31).getTime()).label, 'FY 2025-26');
  assert.equal(financialYear(new Date(2026, 3, 1).getTime()).label, 'FY 2026-27');
});

test('deductions: ELSS, life, health, savings interest, capped at limits', () => {
  const now = new Date(2026, 10, 8).getTime();
  const mk = (id: string, body: string, d: number) => at(id, 'AX-HDFCBK', body, d);
  const l = buildLedger([
    mk('1', 'Rs.30,000.00 debited from A/c XX4821 on 05-06-26 towards LIC life insurance premium. Avl Bal Rs.1,00,000', new Date(2026, 5, 5).getTime()),
    mk('2', 'Rs.18,000.00 debited from A/c XX4821 on 05-07-26 towards Star Health insurance premium. Avl Bal Rs.80,000', new Date(2026, 6, 5).getTime()),
    mk('3', 'Your A/c XX4821 is credited with Rs.2,400.00 on 30-09-26 towards savings interest. Avl Bal Rs.82,400', new Date(2026, 8, 30).getTime()),
    mk('4', 'Rs.99,000.00 debited from A/c XX4821 on 05-02-26 towards LIC life insurance premium. Avl Bal Rs.1,000', new Date(2026, 1, 5).getTime()), // previous FY
  ]);
  const orders = [{ id: 'o', date: new Date(2026, 4, 1).getTime(), scheme: 'Mirae Asset ELSS Tax Saver Fund - Direct Growth', folio: '1', amount: 140000, units: 1000, nav: 140 }];
  const g = Object.fromEntries(deductions(l.transactions, orders, now).map((x) => [x.section, x]));
  assert.equal(g['80C'].total, 170000);
  assert.equal(g['80C'].claimed, 150000);
  assert.equal(g['80D'].total, 18000);
  assert.equal(g['80TTA'].total, 2400);
});

test('capital gains: FIFO lots, realised LTCG reduces harvestable exemption', () => {
  const now = new Date(2026, 10, 8).getTime();
  const y = (yy: number, m: number) => new Date(yy, m, 1).getTime();
  const orders = [
    { id: 'a', date: y(2023, 0), scheme: 'Nifty 50 Index Fund - Direct Growth', folio: '1', amount: 100000, units: 1000, nav: 100 },
    { id: 'b', date: y(2026, 6), scheme: 'Nifty 50 Index Fund - Direct Growth', folio: '1', amount: 30000, units: 200, nav: 150 },
    { id: 'c', date: y(2026, 5), scheme: 'Nifty 50 Index Fund - Direct Growth', folio: '1', amount: -45000, units: -300, nav: 150 }, // sells oldest lot
  ];
  const h = buildHoldings(orders, {})[0];
  h.lastNav = 200;
  h.currentValue = h.units * 200;
  const cg = capitalGains([h], now);
  assert.equal(Math.round(cg.realisedLongTerm), 15000); // 300 × (150 − 100)
  assert.equal(Math.round(cg.unrealisedLongTerm), 70000); // 700 × (200 − 100)
  assert.equal(Math.round(cg.unrealisedShortTerm), 10000); // 200 × (200 − 150)
  assert.equal(Math.round(cg.harvestable), 70000); // min(1.25L − 15k, 70k)
});

test('rent receipts: monthly rows in the FY and escaped HTML', () => {
  const now = Date.now();
  const l = buildLedger(demoMessages(now));
  const months = rentPayments(l.transactions, now);
  assert.ok(months.length >= 1 && months.every((m) => m.amount === 32000));
  const html = rentReceiptsHtml({ tenant: 'A <b>', landlord: 'Rajesh', landlordPan: '', address: 'Flat 1' }, months, now);
  assert.ok(html.includes('A &lt;b&gt;') && html.includes('RENT RECEIPT'));
  assert.ok((html.match(/class="r"/g) ?? []).length === months.length);
});

import { goalProgress, monthlyPace } from '../src/lib/goals';
import { nextSundayEvening, weeklyDigest } from '../src/lib/digest';
import { serviceFor, subscriptionViews, subId } from '../src/lib/subscriptions';

test('subscriptions: cancel guide, yearly cost, charged after cancelling', () => {
  const now = Date.now();
  const l = buildLedger(demoMessages(now));
  const rec = findRecurring(l.transactions, now);
  const netflix = rec.find((r) => /netflix/i.test(r.merchant))!;
  assert.equal(serviceFor(netflix.merchant)?.name, 'Netflix');
  const id = subId(netflix.merchant);
  const views = subscriptionViews(rec, { [id]: { status: 'cancelled', at: netflix.lastCharged - 20 * DAYMS } }, () => netflix.lastCharged);
  const v = views.find((x) => x.id === id)!;
  assert.ok(v.chargedAfterCancel);
  assert.equal(views[0].id, id, 'charged-after-cancel goes first');
  assert.equal(v.yearlyCost, netflix.amount * 12);
  assert.equal(new Date(v.nextDue).getDate(), new Date(netflix.lastCharged).getDate());
  assert.ok(!views.some((x) => /landlord/.test(x.id)), 'rent is not a subscription');
});

test('goals: growth shared in order, pace decides on-track', () => {
  const now = new Date(2026, 10, 8).getTime();
  const mk = (id: string, target: number, monthsAhead: number, createdAt: number) => ({
    id, name: id, target, by: now + monthsAhead * 30.44 * DAYMS, createdAt, startNet: 100000, icon: 'plane' as const,
  });
  const p = goalProgress([mk('trip', 60000, 4, 1), mk('car', 300000, 12, 2)], 180000, 25000, now);
  assert.equal(p[0].saved, 60000);
  assert.ok(p[0].done && p[0].onTrack);
  assert.equal(p[1].saved, 20000);
  assert.ok(Math.abs(p[1].needPerMonth - 280000 / 12) < 50);
  assert.ok(p[1].onTrack); // 25k pace >= ~23.3k need
  assert.ok(!goalProgress([mk('car', 300000, 12, 2)], 120000, 5000, now)[0].onTrack);
  assert.equal(Math.round(monthlyPace([{ date: 0, cash: 0, investments: 0, dues: 0, net: 0 }, { date: 30.44 * DAYMS * 2, cash: 0, investments: 0, dues: 0, net: 20000 }])), 10000);
});

test('weekly digest and Sunday scheduling', () => {
  const now = new Date(2026, 10, 12, 10).getTime(); // Thursday
  const l = buildLedger(demoMessages(now));
  const dg = weeklyDigest(l.transactions, l.accounts, monthForecast(l.transactions, now), wasteInsights(l.transactions, now), now);
  assert.ok(dg.spent > 0 && dg.topCategory);
  assert.match(dg.notification.title, /^Your week: ₹/);
  const sun = new Date(nextSundayEvening(now));
  assert.equal(sun.getDay(), 0);
  assert.equal(sun.getHours(), 19);
  assert.equal(new Date(nextSundayEvening(new Date(2026, 10, 15, 20).getTime())).getDate(), 22);
});

import { makeBackup, readBackup } from '../src/lib/backupFormat';

test('backup: round trip keeps known keys, rejects other files', () => {
  const b = makeBackup([['budgets.v1', '{"total":5}'], ['unknown.v1', '"x"'], ['goals.v1', null]], 1);
  assert.deepEqual(Object.keys(b.data), ['budgets.v1']);
  assert.deepEqual(readBackup(JSON.stringify(b)), [['budgets.v1', '{"total":5}']]);
  assert.throws(() => readBackup('{"hello":1}'), /isn't a Paisa Watch backup/);
  assert.throws(() => readBackup('not json'), /isn't a Paisa Watch backup/);
  assert.deepEqual(readBackup(JSON.stringify({ ...b, data: { 'budgets.v1': 'not json', 'rules.v1': '[]' } })), [['rules.v1', '[]']]);
});

test('bills, renewals, prepaid expiry, FASTag and loan statements are parsed', () => {
  const ref = new Date(2026, 10, 8).getTime();
  const p = (address: string, body: string) => parseSms({ id: '1', address, body, date: ref });
  const elec = p('VM-BESCOM', 'Dear Consumer, BESCOM bill amount Rs.2,340.00 for RR No 12345 is due on 18-11-2026. Pay online to avoid disconnection.');
  assert.ok(elec && elec.type === 'bill');
  assert.equal(elec.biller, 'BESCOM');
  assert.equal(elec.kind, 'electricity');
  assert.equal(elec.amount, 2340);
  assert.equal(new Date(elec.dueDate!).getDate(), 18);
  const ins = p('AX-LICIND', 'Premium of Rs.25,000 for policy 123456789 is due on 20-Nov-2026. Pay before the due date to keep your policy active.');
  assert.ok(ins && ins.type === 'bill' && ins.kind === 'insurance' && ins.amount === 25000);
  // a payment confirmation is not a due bill
  const paid = p('AD-AIRTEL', 'Payment of Rs 999 towards your Airtel bill due on 14-11-2026 has been received. Thank you!');
  assert.ok(!paid || paid.type !== 'bill');
  const exp = p('JM-JIOINF', 'Your Jio plan of Rs 299 expires on 12-Nov-26. Recharge now to continue enjoying services.');
  assert.ok(exp && exp.type === 'expiry' && exp.service === 'Jio' && new Date(exp.expiresOn).getDate() === 12);
  assert.equal(p('JM-JIOINF', 'Offer valid till 30-11-26! Get 20% cashback on recharge.')?.type ?? null, null);
  const tag = p('VM-IDFCFB', 'Your FASTag balance is Rs.142.50. Please recharge to avoid double toll.');
  assert.ok(tag && tag.type === 'fastag' && tag.balance === 142.5);
  const toll = p('VM-IDFCFB', 'Rs.85.00 debited from your FASTag for toll at Electronic City Plaza. Avl Bal Rs.57.50');
  assert.ok(toll && toll.type === 'txn' && toll.accountKind === 'wallet' && toll.balance === 57.5);
  const loan = p('AX-HDFCBK', 'Principal outstanding on your Home Loan A/c XX5566 is Rs.24,50,000 as on 01-11-2026.');
  assert.ok(loan && loan.type === 'loan' && loan.outstanding === 2450000 && loan.last4 === '5566');
});

import { billViews, expiryViews, lowFastags, planBillReminders } from '../src/lib/bills';
import { priceChanges } from '../src/lib/anomalies';
import { detectLoans, monthsToRepay, prepayImpact } from '../src/lib/loans';
import { yearReview } from '../src/lib/review';

test('bills: paid when a matching payment follows; reminders for unpaid and expiring plans', () => {
  const now = new Date(2026, 10, 10, 8).getTime();
  const l = buildLedger([
    at('1', 'VM-BESCOM', 'BESCOM bill amount Rs.2,340.00 for RR No 1 is due on 18-11-2026.', new Date(2026, 10, 3).getTime()),
    at('2', 'AX-LICIND', 'Premium of Rs.25,000 for policy 1 is due on 20-11-2026.', new Date(2026, 10, 4).getTime()),
    at('3', 'AX-HDFCBK', 'Sent Rs.2,340.00 From HDFC Bank A/C *4821 To bescom@billdesk On 06-11-26 Ref 9. Avl Bal Rs.1,000', new Date(2026, 10, 6).getTime()),
    at('4', 'JM-JIOINF', 'Your Jio plan expires on 13-11-2026. Recharge now.', new Date(2026, 10, 9).getTime()),
    at('5', 'VM-IDFCFB', 'Your FASTag balance is Rs.142.50. Please recharge.', new Date(2026, 10, 9).getTime()),
  ]);
  const bv = billViews(l.bills, l.transactions, now);
  assert.equal(bv.find((b) => b.biller === 'BESCOM')!.state, 'paid');
  assert.equal(bv.find((b) => b.biller === 'LIC')!.state, 'due');
  const ev = expiryViews(l.expiries, now);
  assert.equal(ev[0].service, 'Jio');
  assert.equal(lowFastags(l.accounts).length, 1);
  assert.ok(!l.accounts.some((a) => a.kind === 'bank' && a.balance === 142.5), 'FASTag is not a bank account');
  const r = planBillReminders(bv, ev, now);
  assert.equal(r.filter((x) => /LIC/.test(x.title)).length, 2);
  assert.ok(!r.some((x) => /BESCOM/.test(x.title)));
  assert.ok(r.some((x) => /Jio plan expires today/.test(x.title)));
});

test('price rises on subscriptions and unusually high bills', () => {
  const now = new Date(2026, 10, 10).getTime();
  const msgs = [];
  for (let i = 5; i >= 0; i--) {
    const d = new Date(2026, 10 - i, 6).getTime();
    msgs.push(at(`n${i}`, 'JD-ICICIT', `INR ${i === 0 ? '799.00' : '649.00'} spent using ICICI Bank Card XX9034 on 06-1${i}-26 on NETFLIX.COM. Avl Limit: INR 50,000`, d));
    msgs.push(at(`b${i}`, 'VM-BESCOM', `BESCOM bill amount Rs.${i === 0 ? '3,400.00' : '2,000.00'} for RR No 1 is due on 25-1${i}-26.`, new Date(2026, 10 - i, 3).getTime()));
  }
  const l = buildLedger(msgs);
  const ch = priceChanges(l.transactions, l.bills, now);
  const rise = ch.find((c) => c.kind === 'price-rise')!;
  assert.ok(rise && /netflix/i.test(rise.name) && rise.from === 649 && rise.to === 799);
  assert.equal(Math.round(rise.impact), 1800);
  const sp = ch.find((c) => c.kind === 'bill-spike')!;
  assert.ok(sp && sp.name === 'BESCOM' && Math.round(sp.pct * 100) === 70);
});

test('loans: amortisation maths and EMI detection with lender outstanding', () => {
  // ₹10L at 12% with ₹22,244 EMI is ~60 months
  assert.ok(Math.abs(monthsToRepay(1_000_000, 0.01, 22_244) - 60) < 0.5);
  assert.equal(monthsToRepay(100_000, 0.01, 500), Infinity);
  const pp = prepayImpact(1_000_000, 0.12, 22_244, 200_000);
  assert.ok(pp.monthsSaved > 12 && pp.interestSaved > 50_000, JSON.stringify(pp));
  const now = new Date(2026, 10, 10).getTime();
  const msgs = [at('os', 'AX-HDFCBK', 'Principal outstanding on your Home Loan A/c XX5566 is Rs.24,50,000 as on 01-08-2026.', new Date(2026, 7, 1).getTime())];
  for (let i = 0; i < 6; i++) {
    msgs.push(at(`e${i}`, 'AX-HDFCBK', `EMI of Rs.25,000.00 for Home Loan A/c XX5566 debited from A/c XX4821 on 05-0${i + 6}-26. Avl Bal Rs.1,00,000`, new Date(2026, 5 + i, 5).getTime()));
  }
  const loans = detectLoans(buildLedger(msgs).transactions, buildLedger(msgs).loanPoints, {}, now);
  assert.equal(loans.length, 1);
  const L = loans[0];
  assert.equal(L.type, 'home');
  assert.equal(L.emi, 25000);
  assert.equal(L.outstandingSource, 'sms');
  assert.ok(L.outstanding! < 2_450_000 && L.outstanding! > 2_400_000, String(L.outstanding));
  assert.ok(L.monthsLeft! > 100 && L.interestLeft! > 0);
});

test('year in review', () => {
  const now = Date.now();
  const l = buildLedger(demoMessages(now));
  const r = yearReview(l.transactions, netWorthHistory(l, buildHoldings(l.mfOrders), 12, now), now);
  assert.ok(r.spent > 0 && r.income > 0 && r.topMerchants.length > 0);
  assert.ok(r.foodOrders > 10 && r.rides > 10);
  assert.ok(r.personality.name.startsWith('The '));
  assert.equal(r.topMerchants[0].merchant, 'rajeshlandlord');
  assert.ok(r.mostVisited && r.mostVisited.merchant !== 'rajeshlandlord');
});

test('EMI debit is booked to the paying account, not the loan account', () => {
  const p = parseSms(sms('AX-HDFCBK', 'EMI of Rs.25,000.00 for Home Loan A/c XX5566 debited from A/c XX4821 on 05-11-26. Avl Bal Rs.1,00,000'));
  assert.ok(p && p.type === 'txn' && p.last4 === '4821' && p.balance === 100000);
  const q = parseSms(sms('AX-HDFCBK', 'Sent Rs.250.00 From HDFC Bank A/C *1234 To swiggy@icici On 05-11-26'));
  assert.ok(q && q.type === 'txn' && q.last4 === '1234');
});
