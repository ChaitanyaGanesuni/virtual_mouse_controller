import type { WorthPoint } from './history';

export interface Goal {
  id: string;
  name: string;
  target: number;
  by: number; // target date
  createdAt: number;
  /** Net worth when the goal was created; growth since then funds goals in priority order. */
  startNet: number;
  icon: 'plane' | 'home' | 'shield' | 'car' | 'gift' | 'book' | 'heart' | 'sparkle';
}

export interface GoalProgress {
  goal: Goal;
  saved: number;
  pct: number;
  monthsLeft: number;
  needPerMonth: number;
  onTrack: boolean;
  done: boolean;
}

const MONTH = 30.44 * 86_400_000;

/** Average monthly change in net worth over the last few month-end points. */
export function monthlyPace(history: WorthPoint[], months = 3): number {
  if (history.length < 2) return 0;
  const tail = history.slice(-(months + 1));
  const first = tail[0];
  const last = tail[tail.length - 1];
  const span = (last.date - first.date) / MONTH;
  return span > 0 ? (last.net - first.net) / span : 0;
}

/**
 * Growth in net worth since each goal was set is shared out in order (first goal first).
 * A goal is on track if your recent monthly pace, after what earlier goals need, covers what this one needs.
 */
export function goalProgress(goals: Goal[], netNow: number, pace: number, now = Date.now()): GoalProgress[] {
  const ordered = [...goals].sort((a, b) => a.createdAt - b.createdAt);
  let paceLeft = pace;
  const pools = new Map<number, number>(); // startNet -> growth already allocated
  return ordered.map((g) => {
    const growth = Math.max(0, netNow - g.startNet);
    const used = pools.get(g.startNet) ?? 0;
    const saved = Math.min(g.target, Math.max(0, growth - used));
    pools.set(g.startNet, used + saved);
    const remaining = Math.max(0, g.target - saved);
    const monthsLeft = Math.max(0, (g.by - now) / MONTH);
    const needPerMonth = remaining === 0 ? 0 : monthsLeft > 0.5 ? remaining / monthsLeft : remaining;
    const onTrack = remaining === 0 || paceLeft >= needPerMonth;
    paceLeft = Math.max(0, paceLeft - needPerMonth);
    return { goal: g, saved, pct: g.target > 0 ? saved / g.target : 0, monthsLeft, needPerMonth, onTrack, done: remaining === 0 };
  });
}
