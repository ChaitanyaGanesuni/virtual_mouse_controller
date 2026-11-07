import type { RawSms } from './types';

const DAY = 86_400_000;

/** Realistic sample alert SMS for ~6 months, used by "Demo mode" and the tests. */
export function demoMessages(now = Date.now()): RawSms[] {
  const out: RawSms[] = [];
  let id = 1;
  let bal = 64_000;
  let seed = 7;
  const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  const fmt = (n: number) => n.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const d = (ms: number) => {
    const x = new Date(ms);
    return `${String(x.getDate()).padStart(2, '0')}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getFullYear()).slice(2)}`;
  };
  const push = (date: number, address: string, body: string) => out.push({ id: String(id++), address, body, date });

  const upi = (date: number, amt: number, vpa: string) => {
    bal -= amt;
    push(date, 'AX-HDFCBK', `Sent Rs.${fmt(amt)} From HDFC Bank A/C *4821 To ${vpa} On ${d(date)} Ref 4${id}88213 Not You? Call 18002586161. Avl Bal Rs.${fmt(bal)}`);
  };
  const card = (date: number, amt: number, merchant: string) =>
    push(date, 'JD-ICICIT-S', `INR ${fmt(amt)} spent using ICICI Bank Card XX9034 on ${d(date)} on ${merchant}. Avl Limit: INR ${fmt(150000 - amt * 3)}. If not you, call 1800 2662.`);

  for (let m = 5; m >= 0; m--) {
    const start = new Date(new Date(now).getFullYear(), new Date(now).getMonth() - m, 1).getTime();
    const at = (day: number, hour = 12) => start + (day - 1) * DAY + hour * 3_600_000;
    if (at(1) > now) continue;
    const upto = (day: number) => at(day) <= now;

    // Salary
    if (upto(1)) {
      bal += 145_000;
      push(at(1, 10), 'VM-HDFCBK', `Your A/c XX4821 is credited with INR 1,45,000.00 on ${d(at(1))} by NEFT-SALARY ACME TECHNOLOGIES PVT LTD. Avl Bal INR ${fmt(bal)}`);
    }
    // Rent, SIPs
    if (upto(3)) upi(at(3), 32_000, 'rajeshlandlord@okaxis');
    if (upto(5)) {
      bal -= 10_000;
      push(at(5), 'AX-HDFCBK', `Rs.10,000.00 debited from A/c XX4821 on ${d(at(5))} towards NACH BSE STAR MF SIP. Avl Bal Rs.${fmt(bal)}`);
      push(at(7), 'VM-CAMSPL', `Dear Investor, your SIP purchase of Rs.5,000.00 in Folio 7781234/56 under Axis Bluechip Fund - Regular Growth is processed at NAV of ${(52 + (5 - m) * 0.6).toFixed(4)} for ${(5000 / (52 + (5 - m) * 0.6)).toFixed(3)} units.`);
      push(at(7), 'VM-KFINTK', `Dear Investor, your purchase of Rs.5,000.00 in Folio 91234567 under Parag Parikh Flexi Cap Fund - Direct Growth is processed at NAV of ${(78 + (5 - m) * 1.1).toFixed(4)} for ${(5000 / (78 + (5 - m) * 1.1)).toFixed(3)} units.`);
    }
    // Subscriptions on card
    if (upto(6)) card(at(6), 649, 'NETFLIX.COM');
    if (upto(8)) card(at(8), 299, 'HOTSTAR');
    if (upto(9)) card(at(9), 119, 'SPOTIFY INDIA');
    if (upto(11)) card(at(11), 1_999, 'CULT.FIT');
    // Bills
    if (upto(12)) upi(at(12), 1_840 + Math.round(rnd() * 600), 'bescom@billdesk');
    if (upto(14)) upi(at(14), 999, 'airtel@airtelpaymentsbank');
    // Food delivery and dining
    for (let i = 0; i < 9 + m; i++) {
      const day = 1 + Math.floor(rnd() * 27);
      if (upto(day)) upi(at(day, 21), 280 + Math.round(rnd() * 520), rnd() > 0.5 ? 'swiggy@icici' : 'zomato@hdfcbank');
    }
    for (let i = 0; i < 3; i++) {
      const day = 1 + Math.floor(rnd() * 27);
      if (upto(day)) card(at(day, 20), 1_200 + Math.round(rnd() * 2_500), 'TOIT BREWPUB');
    }
    // Groceries
    for (let i = 0; i < 6; i++) {
      const day = 1 + Math.floor(rnd() * 27);
      if (upto(day)) upi(at(day), 400 + Math.round(rnd() * 1800), rnd() > 0.5 ? 'blinkit@hdfcbank' : 'bigbasket@ybl');
    }
    // Cabs
    for (let i = 0; i < 10; i++) {
      const day = 1 + Math.floor(rnd() * 27);
      if (upto(day)) upi(at(day, 9), 150 + Math.round(rnd() * 350), 'uber@axisbank');
    }
    // Shopping
    for (let i = 0; i < 3; i++) {
      const day = 1 + Math.floor(rnd() * 27);
      if (upto(day)) card(at(day), 600 + Math.round(rnd() * (m === 0 ? 9000 : 3000)), rnd() > 0.5 ? 'AMAZON' : 'MYNTRA');
    }
    // Card bill + statement
    if (upto(18)) {
      const due = 18_000 + Math.round(rnd() * 6_000);
      push(at(18), 'JD-ICICIT-S', `ICICI Bank Credit Card XX9034 statement: Total Amt Due Rs ${fmt(due)}. Min Amt Due Rs ${fmt(due * 0.05)}. Pay by ${d(at(28))}.`);
      const paid = m === 2 ? due - 8000 : due;
      if (upto(25)) {
        bal -= paid;
        push(at(25), 'AX-HDFCBK', `Rs.${fmt(paid)} debited from A/c XX4821 on ${d(at(25))} towards ICICI Credit Card bill payment via BillDesk. Avl Bal Rs.${fmt(bal)}`);
        push(at(25, 14), 'JD-ICICIT-S', `Dear Customer, Payment of INR ${fmt(paid)} has been received on your ICICI Bank Credit Card Account XX9034. Thank you.`);
      }
    }
    if (m === 1 && upto(20)) {
      card(at(20), 1_180, 'FINANCE CHARGES INTEREST');
      card(at(20), 700, 'LATE PAYMENT FEE');
    }
    // Weekend betting habit
    if (m <= 2 && upto(16)) upi(at(16), 500, 'dream11@icici');
    // ATM
    if (upto(15)) {
      bal -= 3000;
      push(at(15), 'AX-HDFCBK', `Rs.3,000.00 withdrawn at HDFC ATM from A/c XX4821 on ${d(at(15))}. Avl Bal Rs.${fmt(bal)}`);
    }
  }
  // Noise that must be ignored
  push(now - DAY, 'AX-HDFCBK', 'OTP for txn of Rs.4,999.00 at AMAZON is 482913. Do not share.');
  push(now - DAY, 'VM-HDFCBK', 'Pre-approved personal loan of Rs.5,00,000 ready! Apply now.');
  push(now - DAY, '+919812345678', 'Hey, sent you Rs 500 for dinner');
  return out;
}
