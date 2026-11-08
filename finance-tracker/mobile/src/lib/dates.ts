const MON: Record<string, number> = {
  jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, sept: 8, oct: 9, nov: 10, dec: 11,
};

const year = (y: string) => {
  const n = parseInt(y, 10);
  return y.length <= 2 ? 2000 + n : n;
};

const make = (y: number, m: number, d: number): number | null => {
  if (m < 0 || m > 11 || d < 1 || d > 31 || y < 2000 || y > 2100) return null;
  const t = new Date(y, m, d, 12, 0, 0);
  return t.getMonth() === m ? t.getTime() : null;
};

/**
 * Finds the first date in an Indian bank SMS fragment. Handles 28-11-26, 28/11/2026, 28.11.2026,
 * 28-Nov-26, 28 Nov 2026, 28Nov26, Nov 28, 2026 and "28 Nov" (year inferred from `ref`).
 */
export function parseDateText(s: string, ref = Date.now()): number | null {
  let m = /\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b/.exec(s);
  if (m) return make(year(m[3]), parseInt(m[2], 10) - 1, parseInt(m[1], 10));

  m = /\b(\d{1,2})[-\s]?([A-Za-z]{3})[a-z]*[-\s,]*(\d{4}|\d{2})?\b/.exec(s);
  if (m && MON[m[2].toLowerCase()] !== undefined) {
    const mon = MON[m[2].toLowerCase()];
    if (m[3]) return make(year(m[3]), mon, parseInt(m[1], 10));
    return inferYear(mon, parseInt(m[1], 10), ref);
  }

  m = /\b([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s*(\d{4})?\b/.exec(s);
  if (m && MON[m[1].toLowerCase()] !== undefined) {
    const mon = MON[m[1].toLowerCase()];
    if (m[3]) return make(year(m[3]), mon, parseInt(m[2], 10));
    return inferYear(mon, parseInt(m[2], 10), ref);
  }
  return null;
}

/** A due date without a year is the next occurrence on or after ~2 months before `ref`. */
function inferYear(mon: number, day: number, ref: number): number | null {
  const y = new Date(ref).getFullYear();
  for (const cand of [y - 1, y, y + 1]) {
    const t = make(cand, mon, day);
    if (t != null && t >= ref - 60 * 86_400_000) return t;
  }
  return null;
}
