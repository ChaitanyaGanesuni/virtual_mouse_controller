import type { Ledger } from './ledger';
import type { Holding } from './types';

export interface WorthPoint {
  date: number;
  cash: number;
  investments: number;
  dues: number;
  net: number;
}

const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, '');

/**
 * Rebuilds month-end net worth from what the SMS history says at each point in time:
 * bank balances (last balance reported per account), card dues (last statement minus payments since),
 * and mutual funds (units held × the NAV of the latest order). The final point uses today's live values.
 */
export function netWorthHistory(ledger: Ledger, holdings: Holding[], months = 12, now = Date.now()): WorthPoint[] {
  const d = new Date(now);
  const ends: number[] = [];
  for (let i = months - 1; i >= 1; i--) ends.push(new Date(d.getFullYear(), d.getMonth() - i + 1, 0, 23, 59, 59).getTime());

  const bankKeys = [...new Set(ledger.balancePoints.map((p) => p.key))];
  const cardKeys = [...new Set(ledger.cardEvents.map((e) => e.key))];
  const firstData = Math.min(
    ...ledger.balancePoints.map((p) => p.date),
    ...ledger.cardEvents.map((e) => e.date),
    ...ledger.mfOrders.map((o) => o.date),
    now,
  );

  const at = (t: number): WorthPoint => {
    let cash = 0;
    for (const k of bankKeys) {
      let last: number | null = null;
      for (const p of ledger.balancePoints) if (p.key === k && p.date <= t) last = p.balance;
      cash += last ?? 0;
    }
    let dues = 0;
    for (const k of cardKeys) {
      let due = 0;
      for (const e of ledger.cardEvents) {
        if (e.key !== k || e.date > t) continue;
        due = e.kind === 'statement' ? e.amount : Math.max(0, due - e.amount);
      }
      dues += due;
    }
    const units = new Map<string, { units: number; nav: number }>();
    for (const o of ledger.mfOrders) {
      if (o.date > t) continue;
      const k = norm(o.scheme) + '|' + o.folio;
      const u = units.get(k) ?? { units: 0, nav: 0 };
      u.units += o.units;
      u.nav = o.nav;
      units.set(k, u);
    }
    const investments = [...units.values()].reduce((s, u) => s + Math.max(0, u.units) * u.nav, 0);
    return { date: t, cash, investments, dues, net: cash + investments - dues };
  };

  const points = ends.filter((t) => t >= firstData).map(at);
  const live = at(now);
  live.investments = holdings.reduce((s, h) => s + h.currentValue, 0) || live.investments;
  const bankNow = ledger.accounts.filter((a) => a.kind === 'bank').reduce((s, a) => s + (a.balance ?? 0), 0);
  const duesNow = ledger.accounts.filter((a) => a.kind === 'credit_card').reduce((s, a) => s + (a.balance ?? 0), 0);
  live.cash = bankNow;
  live.dues = duesNow;
  live.net = live.cash + live.investments - live.dues;
  points.push(live);
  return points;
}
