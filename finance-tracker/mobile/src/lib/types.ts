export type Direction = 'debit' | 'credit';
export type AccountKind = 'bank' | 'credit_card';

export interface RawSms {
  id: string;
  address: string; // sender id, e.g. "AX-HDFCBK"
  body: string;
  date: number; // epoch ms
}

export interface Transaction {
  id: string; // sms id
  date: number; // epoch ms
  amount: number;
  direction: Direction;
  accountKey: string; // `${institution}|${kind}|${last4}`
  institution: string;
  accountKind: AccountKind;
  last4: string;
  merchant: string;
  mode: string; // UPI, CARD, ATM, NEFT, IMPS, AUTOPAY, OTHER
  category: string;
  body: string;
}

export interface Account {
  key: string;
  institution: string;
  kind: AccountKind;
  last4: string;
  /** Bank: available balance. Card: amount owed (if known). */
  balance: number | null;
  /** Credit cards only: available limit. */
  availableLimit: number | null;
  asOf: number | null;
}

export interface MfOrder {
  id: string;
  date: number;
  scheme: string;
  folio: string;
  amount: number; // positive = invested, negative = redeemed
  units: number; // positive = bought, negative = sold
  nav: number;
}

export interface Holding {
  scheme: string;
  folio: string;
  units: number;
  invested: number; // net cash put in
  lastNav: number;
  navDate: number | null;
  currentValue: number;
  assetClass: 'equity' | 'debt' | 'hybrid' | 'gold';
  plan: 'direct' | 'regular' | 'unknown';
  orders: MfOrder[];
}

export type Severity = 'high' | 'medium' | 'low';

export interface Insight {
  id: string;
  title: string;
  detail: string;
  severity: Severity;
  /** Money lost/wasted over the analysed window (or per year for investments). */
  amount?: number;
  /** Estimated saving per month if acted on. */
  monthlySaving?: number;
  transactionIds?: string[];
}
