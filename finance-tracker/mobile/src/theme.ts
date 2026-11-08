import type { IconName } from './components/Icon';

export type Mode = 'dark' | 'light';
export type Accent = 'emerald' | 'indigo' | 'violet' | 'sunset' | 'ocean';

const NEUTRAL: Record<Mode, Record<string, string>> = {
  dark: {
    bg: '#0A0B12',
    bg2: '#0F111B',
    card: '#141725',
    cardHi: '#1C2033',
    border: '#22273F',
    borderHi: '#30365A',
    text: '#F2F4FA',
    sub: '#9AA3B8',
    faint: '#646C84',
    glass: 'rgba(20,23,37,0.94)',
    shadow: '#000000',
  },
  light: {
    bg: '#F2F3F8',
    bg2: '#FFFFFF',
    card: '#FFFFFF',
    cardHi: '#EDEFF6',
    border: '#E4E7F0',
    borderHi: '#D3D8E6',
    text: '#11142A',
    sub: '#596179',
    faint: '#8F96AA',
    glass: 'rgba(255,255,255,0.95)',
    shadow: '#1B2240',
  },
};

/** Status colours: money in/out, warnings. Fixed meaning whatever accent you pick. */
const STATUS: Record<Mode, Record<string, string>> = {
  dark: {
    green: '#34D399', greenDeep: '#0F9F74', teal: '#2DD4BF', blue: '#60A5FA', indigo: '#818CF8',
    violet: '#A78BFA', amber: '#FBBF24', orange: '#FB923C', red: '#F87171', pink: '#F472B6',
  },
  light: {
    green: '#059669', greenDeep: '#047857', teal: '#0D9488', blue: '#2563EB', indigo: '#4F46E5',
    violet: '#7C3AED', amber: '#D97706', orange: '#EA580C', red: '#DC2626', pink: '#DB2777',
  },
};

export const ACCENTS: Record<Accent, { label: string; dark: string; light: string; onDark: string; hero: readonly string[] }> = {
  emerald: { label: 'Emerald', dark: '#34D399', light: '#059669', onDark: '#03261A', hero: ['#059669', '#0E7490', '#312E81'] },
  indigo: { label: 'Indigo', dark: '#8B93FF', light: '#4F46E5', onDark: '#0B0B2E', hero: ['#4F46E5', '#7C3AED', '#C026D3'] },
  violet: { label: 'Violet', dark: '#C084FC', light: '#9333EA', onDark: '#2A0B3D', hero: ['#7C3AED', '#C026D3', '#F43F5E'] },
  sunset: { label: 'Sunset', dark: '#FB923C', light: '#EA580C', onDark: '#3A1300', hero: ['#F97316', '#E11D48', '#7C3AED'] },
  ocean: { label: 'Ocean', dark: '#38BDF8', light: '#0284C7', onDark: '#032033', hero: ['#0284C7', '#0891B2', '#4F46E5'] },
};

/**
 * Live colour tokens. `applyTheme` swaps the values in place, and the app re-mounts its screens,
 * so every component reading `C.x` at render time picks up the new theme.
 */
export const C = {
  ...NEUTRAL.dark,
  ...STATUS.dark,
  accent: ACCENTS.emerald.dark,
  onAccent: ACCENTS.emerald.onDark,
  accentSoft: ACCENTS.emerald.dark + '22',
} as Record<
  | 'bg' | 'bg2' | 'card' | 'cardHi' | 'border' | 'borderHi' | 'text' | 'sub' | 'faint' | 'glass' | 'shadow'
  | 'green' | 'greenDeep' | 'teal' | 'blue' | 'indigo' | 'violet' | 'amber' | 'orange' | 'red' | 'pink'
  | 'accent' | 'onAccent' | 'accentSoft',
  string
>;

export const theme = { mode: 'dark' as Mode, accent: 'emerald' as Accent };

export function applyTheme(mode: Mode, accent: Accent): void {
  const a = ACCENTS[accent];
  Object.assign(C, NEUTRAL[mode], STATUS[mode], {
    accent: mode === 'dark' ? a.dark : a.light,
    onAccent: mode === 'dark' ? a.onDark : '#FFFFFF',
    accentSoft: (mode === 'dark' ? a.dark : a.light) + (mode === 'dark' ? '24' : '1A'),
  });
  GRADIENTS.hero = a.hero;
  theme.mode = mode;
  theme.accent = accent;
}

export const F = {
  regular: 'Inter_400Regular',
  medium: 'Inter_500Medium',
  semibold: 'Inter_600SemiBold',
  bold: 'Inter_700Bold',
  black: 'Inter_800ExtraBold',
};

export const R = { sm: 10, md: 16, lg: 22, xl: 28, pill: 999 };

export const GRADIENTS: Record<'hero' | 'save' | 'invest' | 'warn', readonly string[]> = {
  hero: ['#059669', '#0E7490', '#312E81'],
  save: ['#065F46', '#047857', '#0F766E'],
  invest: ['#312E81', '#4C1D95', '#6D28D9'],
  warn: ['#9A3412', '#B45309', '#BE123C'],
};

export interface CategoryMeta {
  color: string;
  icon: IconName;
}

const CAT: Record<string, CategoryMeta> = {
  'Food Delivery': { color: '#FB923C', icon: 'bag' },
  'Dining Out': { color: '#F472B6', icon: 'coffee' },
  Groceries: { color: '#34D399', icon: 'cart' },
  Shopping: { color: '#A78BFA', icon: 'gift' },
  Subscriptions: { color: '#F87171', icon: 'repeat' },
  Cabs: { color: '#FBBF24', icon: 'car' },
  Transport: { color: '#FCD34D', icon: 'fuel' },
  Travel: { color: '#38BDF8', icon: 'plane' },
  Entertainment: { color: '#E879F9', icon: 'film' },
  'Bills & Utilities': { color: '#60A5FA', icon: 'bolt' },
  'Rent & Housing': { color: '#818CF8', icon: 'home' },
  'EMI & Loans': { color: '#FDA4AF', icon: 'bank' },
  Insurance: { color: '#5EEAD4', icon: 'shield' },
  Health: { color: '#4ADE80', icon: 'heart' },
  Education: { color: '#93C5FD', icon: 'book' },
  'Cash Withdrawal': { color: '#A3E635', icon: 'cash' },
  'Fees & Charges': { color: '#EF4444', icon: 'alert' },
  'Card Bill Payment': { color: '#94A3B8', icon: 'card' },
  'Self Transfer': { color: '#94A3B8', icon: 'swap' },
  Investments: { color: '#818CF8', icon: 'trend' },
  Salary: { color: '#34D399', icon: 'briefcase' },
  Income: { color: '#34D399', icon: 'arrowDown' },
  'Interest & Dividends': { color: '#2DD4BF', icon: 'percent' },
  Refund: { color: '#5EEAD4', icon: 'undo' },
  Reversed: { color: '#94A3B8', icon: 'undo' },
  'UPI Payments (Other)': { color: '#7DD3FC', icon: 'send' },
  Other: { color: '#94A3B8', icon: 'dots' },
};

export const catMeta = (c: string): CategoryMeta => CAT[c] ?? CAT.Other;

/** Read at render time so it follows the current theme. */
export const severity = () => ({
  high: { color: C.red, label: 'Losing money', icon: 'alert' as IconName },
  medium: { color: C.amber, label: 'Worth trimming', icon: 'scissors' as IconName },
  low: { color: C.blue, label: 'Worth a look', icon: 'eye' as IconName },
});
