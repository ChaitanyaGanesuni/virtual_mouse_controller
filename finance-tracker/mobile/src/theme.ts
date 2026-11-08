import type { IconName } from './components/Icon';

export const C = {
  bg: '#090D14',
  bg2: '#0D131D',
  card: '#121A26',
  cardHi: '#182233',
  border: '#1E2A3C',
  borderHi: '#2A3A52',
  text: '#EEF2F8',
  sub: '#8A97AB',
  faint: '#5A677C',
  green: '#34D399',
  greenDeep: '#0F9F74',
  teal: '#2DD4BF',
  blue: '#60A5FA',
  indigo: '#818CF8',
  violet: '#A78BFA',
  amber: '#FBBF24',
  orange: '#FB923C',
  red: '#F87171',
  pink: '#F472B6',
};

export const F = {
  regular: 'Inter_400Regular',
  medium: 'Inter_500Medium',
  semibold: 'Inter_600SemiBold',
  bold: 'Inter_700Bold',
  black: 'Inter_800ExtraBold',
};

export const R = { sm: 10, md: 16, lg: 22, xl: 28, pill: 999 };

export const GRADIENTS = {
  hero: ['#0F9F74', '#0E7490', '#312E81'] as const,
  save: ['#064E3B', '#065F46'] as const,
  invest: ['#312E81', '#4C1D95'] as const,
  warn: ['#7C2D12', '#78350F'] as const,
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
  'UPI Payments (Other)': { color: '#7DD3FC', icon: 'send' },
  Other: { color: '#94A3B8', icon: 'dots' },
};

export const catMeta = (c: string): CategoryMeta => CAT[c] ?? CAT.Other;

export const SEVERITY = {
  high: { color: C.red, label: 'Losing money', icon: 'alert' as IconName },
  medium: { color: C.amber, label: 'Worth trimming', icon: 'scissors' as IconName },
  low: { color: C.blue, label: 'Worth a look', icon: 'eye' as IconName },
};
