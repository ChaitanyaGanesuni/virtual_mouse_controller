import { inr, isIncome, isInvestment, isSpend } from './analysis';
import type { Account, Holding, Insight, MfOrder, Transaction } from './types';

const DAY = 86_400_000;

export function assetClassOf(name: string): Holding['assetClass'] {
  const n = name.toLowerCase();
  if (/gold|silver/.test(n)) return 'gold';
  if (/liquid|overnight|money market|debt|gilt|bond|corporate|banking & psu|banking and psu|credit risk|duration|floater|treasury|income fund|g-sec|sdl|target maturity/.test(n)) return 'debt';
  if (/hybrid|balanced|arbitrage|asset allocation|multi asset|equity savings|dynamic asset|advantage/.test(n)) return 'hybrid';
  return 'equity';
}

export function planOf(name: string): Holding['plan'] {
  if (/\bdirect\b|\bdir\b/i.test(name)) return 'direct';
  if (/\bregular\b|\breg\b/i.test(name)) return 'regular';
  return 'unknown';
}

const normScheme = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, '');

export function buildHoldings(orders: MfOrder[], navs: Record<string, { nav: number; date: number }> = {}): Holding[] {
  const map = new Map<string, Holding>();
  for (const o of [...orders].sort((a, b) => a.date - b.date)) {
    const key = normScheme(o.scheme) + '|' + o.folio;
    let h = map.get(key);
    if (!h) {
      h = {
        scheme: o.scheme,
        folio: o.folio,
        units: 0,
        invested: 0,
        lastNav: 0,
        navDate: null,
        currentValue: 0,
        assetClass: assetClassOf(o.scheme),
        plan: planOf(o.scheme),
        orders: [],
      };
      map.set(key, h);
    }
    h.units += o.units;
    h.invested += o.amount;
    h.lastNav = o.nav;
    h.navDate = o.date;
    h.orders.push(o);
  }
  const out: Holding[] = [];
  for (const h of map.values()) {
    if (h.units < 0.001) continue; // fully redeemed
    const live = navs[normScheme(h.scheme)];
    if (live && (!h.navDate || live.date >= h.navDate)) {
      h.lastNav = live.nav;
      h.navDate = live.date;
    }
    h.currentValue = h.units * h.lastNav;
    out.push(h);
  }
  return out.sort((a, b) => b.currentValue - a.currentValue);
}

/** XIRR via Newton-Raphson with bisection fallback. Flows: negative = invested, positive = received. */
export function xirr(flows: { date: number; amount: number }[]): number | null {
  if (flows.length < 2 || !flows.some((f) => f.amount < 0) || !flows.some((f) => f.amount > 0)) return null;
  const t0 = Math.min(...flows.map((f) => f.date));
  const years = flows.map((f) => (f.date - t0) / (365 * DAY));
  const npv = (r: number) => flows.reduce((s, f, i) => s + f.amount / Math.pow(1 + r, years[i]), 0);
  let lo = -0.99;
  let hi = 10;
  if (npv(lo) * npv(hi) > 0) return null;
  for (let i = 0; i < 200; i++) {
    const mid = (lo + hi) / 2;
    if (npv(lo) * npv(mid) <= 0) hi = mid;
    else lo = mid;
    if (hi - lo < 1e-7) break;
  }
  return (lo + hi) / 2;
}

export function portfolioXirr(holdings: Holding[], now = Date.now()): number | null {
  const flows = holdings.flatMap((h) => h.orders.map((o) => ({ date: o.date, amount: -o.amount })));
  const value = holdings.reduce((s, h) => s + h.currentValue, 0);
  if (value <= 0) return null;
  flows.push({ date: now, amount: value });
  return xirr(flows);
}

export interface Assumptions {
  emergencyFundMonths: number;
  savingsRate: number; // savings account interest
  liquidFundRate: number;
  regularDirectGap: number; // annual expense ratio difference
  target: { equity: number; debt: number; gold: number }; // % of portfolio
}

export const DEFAULT_ASSUMPTIONS: Assumptions = {
  emergencyFundMonths: 6,
  savingsRate: 0.03,
  liquidFundRate: 0.065,
  regularDirectGap: 0.0075,
  target: { equity: 60, debt: 30, gold: 10 },
};

export function investmentInsights(
  holdings: Holding[],
  accounts: Account[],
  txns: Transaction[],
  a: Assumptions = DEFAULT_ASSUMPTIONS,
  now = Date.now(),
): Insight[] {
  const out: Insight[] = [];
  const total = holdings.reduce((s, h) => s + h.currentValue, 0);

  // 1. Regular plans: commission paid to distributors every year.
  const regular = holdings.filter((h) => h.plan === 'regular');
  if (regular.length) {
    const val = regular.reduce((s, h) => s + h.currentValue, 0);
    const yearly = val * a.regularDirectGap;
    const tenYear = val * (Math.pow(1.12, 10) - Math.pow(1.12 - a.regularDirectGap, 10));
    out.push({
      id: 'regular-plans',
      title: `Switch ${regular.length} fund(s) from Regular to Direct`,
      detail:
        regular.map((h) => `• ${h.scheme}`).join('\n') +
        `\n\nRegular plans charge ~${(a.regularDirectGap * 100).toFixed(2)}% more every year as distributor commission: about ${inr(yearly)}/year now, ` +
        `and roughly ${inr(tenYear)} of lost growth over 10 years at 12% returns. Mind exit loads and capital-gains tax before switching; ` +
        'routing new SIPs into the Direct plan costs nothing.',
      severity: 'high',
      amount: yearly,
      monthlySaving: yearly / 12,
    });
  }

  // 2. Idle cash vs emergency fund.
  const spendTxns = txns.filter((t) => isSpend(t) && t.date >= now - 90 * DAY);
  const monthlySpend = spendTxns.reduce((s, t) => s + t.amount, 0) / 3;
  const cash = accounts.filter((x) => x.kind === 'bank' && x.balance != null).reduce((s, x) => s + (x.balance ?? 0), 0);
  const buffer = monthlySpend * a.emergencyFundMonths;
  if (monthlySpend > 0 && cash > buffer * 1.2 && cash - buffer > 25_000) {
    const idle = cash - buffer;
    const lost = idle * (a.liquidFundRate - a.savingsRate);
    out.push({
      id: 'idle-cash',
      title: `${inr(idle)} sitting idle in savings accounts`,
      detail:
        `You hold ${inr(cash)} in bank accounts vs ~${inr(buffer)} needed for a ${a.emergencyFundMonths}-month emergency fund ` +
        `(based on ${inr(monthlySpend)}/month spending). Moving the excess to a liquid fund / sweep FD (~${(a.liquidFundRate * 100).toFixed(1)}%) ` +
        `instead of ~${(a.savingsRate * 100).toFixed(1)}% would earn about ${inr(lost)} more a year; anything not needed for 5+ years belongs in your long-term SIPs.`,
      severity: 'medium',
      amount: lost,
      monthlySaving: lost / 12,
    });
  } else if (monthlySpend > 0 && cash < buffer * 0.5) {
    out.push({
      id: 'low-emergency',
      title: 'Emergency fund looks thin',
      detail: `Bank balances (${inr(cash)}) cover about ${(cash / monthlySpend).toFixed(1)} months of spending. Build this to ${a.emergencyFundMonths} months before taking more equity risk.`,
      severity: 'medium',
    });
  }

  // 3. Credit-card interest beats any investment return.
  const cardInterest = txns.filter((t) => t.category === 'Fees & Charges' && /interest|finance charge/i.test(t.body) && t.date >= now - 180 * DAY);
  if (cardInterest.length) {
    out.push({
      id: 'card-debt',
      title: 'Pay off card debt before investing more',
      detail: 'Revolving credit-card balances cost 36–42% a year; no investment reliably beats that. Use SIP money to clear the card first.',
      severity: 'high',
      transactionIds: cardInterest.map((t) => t.id),
    });
  }

  // 4. Savings / investing rate.
  const last90 = txns.filter((t) => t.date >= now - 90 * DAY);
  const income = last90.filter(isIncome).reduce((s, t) => s + t.amount, 0);
  const invested = last90.filter(isInvestment).reduce((s, t) => s + t.amount, 0);
  if (income > 0) {
    const rate = invested / income;
    if (rate < 0.2) {
      out.push({
        id: 'invest-rate',
        title: `You invest ${Math.round(rate * 100)}% of income`,
        detail:
          `${inr(invested / 3)}/month invested vs ${inr(income / 3)}/month income. Aim for 20%+. ` +
          `Raising your SIP by ${inr(Math.max(0, income / 3 * 0.2 - invested / 3))}/month gets you there; the waste you cut on the Insights tab can fund it.`,
        severity: rate < 0.1 ? 'high' : 'medium',
      });
    }
  }

  if (!holdings.length) return out;

  // 5. Asset allocation vs target.
  const alloc = { equity: 0, debt: 0, hybrid: 0, gold: 0 };
  for (const h of holdings) alloc[h.assetClass] += h.currentValue;
  const eqPct = ((alloc.equity + alloc.hybrid * 0.5) / total) * 100;
  const debtPct = ((alloc.debt + alloc.hybrid * 0.5) / total) * 100;
  const goldPct = (alloc.gold / total) * 100;
  const drift = Math.max(Math.abs(eqPct - a.target.equity), Math.abs(debtPct - a.target.debt), Math.abs(goldPct - a.target.gold));
  if (drift > 10) {
    out.push({
      id: 'allocation',
      title: 'Portfolio has drifted from your target mix',
      detail:
        `Now: equity ${eqPct.toFixed(0)}%, debt ${debtPct.toFixed(0)}%, gold ${goldPct.toFixed(0)}%. ` +
        `Target: ${a.target.equity}/${a.target.debt}/${a.target.gold}. Rebalance by directing new SIPs to the under-weight asset (no tax), rather than selling.`,
      severity: 'medium',
    });
  }

  // 6. Concentration.
  const top = holdings[0];
  if (holdings.length > 1 && top.currentValue / total > 0.4) {
    out.push({
      id: 'concentration',
      title: `${Math.round((top.currentValue / total) * 100)}% in one fund`,
      detail: `${top.scheme} dominates the portfolio. Consider spreading new money across 3–5 funds with different styles.`,
      severity: 'low',
    });
  }

  // 7. Too many funds = overlap.
  const equityFunds = holdings.filter((h) => h.assetClass === 'equity');
  if (equityFunds.length > 6) {
    out.push({
      id: 'overlap',
      title: `${equityFunds.length} equity funds is probably too many`,
      detail: 'Beyond 4–5 diversified equity funds the portfolios largely overlap (same top stocks), so you pay several fund managers for an index-like result. Consolidate into a few funds or a low-cost index fund.',
      severity: 'low',
    });
  }

  // 8. Underperformers.
  for (const h of holdings) {
    const flows = h.orders.map((o) => ({ date: o.date, amount: -o.amount }));
    flows.push({ date: now, amount: h.currentValue });
    const r = xirr(flows);
    const ageDays = (now - Math.min(...h.orders.map((o) => o.date))) / DAY;
    if (r != null && ageDays > 3 * 365 && h.assetClass === 'equity' && r < 0.08) {
      out.push({
        id: `under-${h.scheme}`,
        title: `${h.scheme} returned ${(r * 100).toFixed(1)}%/yr`,
        detail: 'Over 3+ years an equity fund should beat a fixed deposit. Compare it with a Nifty 50 / Nifty 500 index fund; if it keeps lagging, redirect new SIPs.',
        severity: 'medium',
      });
    }
  }

  return out;
}

/** Fetches the latest NAV for each scheme from the free mfapi.in service. */
export async function fetchNavs(schemes: string[]): Promise<Record<string, { nav: number; date: number }>> {
  const out: Record<string, { nav: number; date: number }> = {};
  for (const scheme of schemes) {
    try {
      const q = scheme.replace(/[^A-Za-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim();
      const search = (await (await fetch(`https://api.mfapi.in/mf/search?q=${encodeURIComponent(q)}`)).json()) as {
        schemeCode: number;
        schemeName: string;
      }[];
      if (!search.length) continue;
      const wantDirect = planOf(scheme) === 'direct';
      const wantGrowth = !/idcw|dividend/i.test(scheme);
      const pick =
        search.find((s) => planOf(s.schemeName) === (wantDirect ? 'direct' : 'regular') && /growth/i.test(s.schemeName) === wantGrowth) ??
        search[0];
      const data = (await (await fetch(`https://api.mfapi.in/mf/${pick.schemeCode}/latest`)).json()) as {
        data: { date: string; nav: string }[];
      };
      const latest = data.data?.[0];
      if (!latest) continue;
      const [dd, mm, yyyy] = latest.date.split('-').map(Number);
      out[normScheme(scheme)] = { nav: parseFloat(latest.nav), date: new Date(yyyy, mm - 1, dd).getTime() };
    } catch {
      // offline or not found: keep the NAV from the last SMS
    }
  }
  return out;
}
