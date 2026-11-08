/**
 * Parses Indian bank / credit-card / UPI / mutual-fund alert SMS into structured data.
 * Pure functions: no React Native imports, so it is unit-testable in Node.
 */
import { parseDateText } from './dates';
import type { AccountKind, Direction, MfOrder, RawSms } from './types';

const NUM = String.raw`([\d,]+(?:\.\d{1,2})?)`;

export type ParsedSms =
  | {
      type: 'txn';
      amount: number;
      direction: Direction;
      institution: string;
      accountKind: AccountKind;
      last4: string;
      merchant: string;
      mode: string;
      balance: number | null;
      availableLimit: number | null;
    }
  | { type: 'card_due'; institution: string; last4: string; amountDue: number; minDue: number | null; dueDate: number | null }
  | { type: 'balance'; institution: string; last4: string; balance: number }
  | { type: 'mf'; order: Omit<MfOrder, 'id' | 'date'> }
  /** Money was taken but the payment failed; a reversal is owed. */
  | { type: 'failed'; institution: string; last4: string; amount: number; mode: string }
  /** A bill or premium that is due (utilities, phone/broadband, insurance renewals…). */
  | { type: 'bill'; biller: string; kind: BillKind; amount: number; dueDate: number | null }
  /** A prepaid plan / pack that expires on a date. */
  | { type: 'expiry'; service: string; expiresOn: number }
  /** FASTag balance update without a toll debit. */
  | { type: 'fastag'; issuer: string; balance: number }
  /** Outstanding balance on a loan account. */
  | { type: 'loan'; lender: string; last4: string; outstanding: number };

export type BillKind = 'electricity' | 'gas' | 'water' | 'phone & internet' | 'tv' | 'insurance' | 'other';

const BILLERS: [RegExp, string, BillKind][] = [
  [/BESCOM/i, 'BESCOM', 'electricity'],
  [/TATAPW|TATA ?POWER/i, 'Tata Power', 'electricity'],
  [/ADANI ?E|AEML/i, 'Adani Electricity', 'electricity'],
  [/MSEDCL|MAHADISCOM|MAHAVITARAN/i, 'MSEDCL', 'electricity'],
  [/BSES/i, 'BSES', 'electricity'],
  [/TORRENT/i, 'Torrent Power', 'electricity'],
  [/TNEB|TANGEDCO/i, 'TNEB', 'electricity'],
  [/KSEB/i, 'KSEB', 'electricity'],
  [/CESC/i, 'CESC', 'electricity'],
  [/IGL|MGL|INDANE|HPGAS|BHARATGAS|GAIL ?GAS/i, 'Gas', 'gas'],
  [/AIRTEL/i, 'Airtel', 'phone & internet'],
  [/JIO/i, 'Jio', 'phone & internet'],
  [/VODAFONE|VIINDIA|\bVI\b|VILTD/i, 'Vi', 'phone & internet'],
  [/BSNL/i, 'BSNL', 'phone & internet'],
  [/ACTFIB|ACT ?FIBERNET/i, 'ACT Fibernet', 'phone & internet'],
  [/HATHWAY/i, 'Hathway', 'phone & internet'],
  [/TATAPLAY|TATASKY|TATA ?PLAY|DISHTV|D2H|SUNDIRECT/i, 'DTH', 'tv'],
  [/LICIND|\bLIC\b/i, 'LIC', 'insurance'],
  [/STARHEALTH|STAR ?HEALTH/i, 'Star Health', 'insurance'],
  [/HDFCERGO|HDFC ?ERGO/i, 'HDFC ERGO', 'insurance'],
  [/HDFCLIFE|HDFC ?LIFE/i, 'HDFC Life', 'insurance'],
  [/ICICIPRU|ICICI ?PRU/i, 'ICICI Prudential', 'insurance'],
  [/SBILIFE|SBI ?LIFE/i, 'SBI Life', 'insurance'],
  [/MAXLIFE|MAX ?LIFE|AXISMAX/i, 'Max Life', 'insurance'],
  [/TATAAIA|TATA ?AIA/i, 'Tata AIA', 'insurance'],
  [/NIVABUPA|NIVA ?BUPA|CAREHEALTH|CARE ?HEALTH|ACKO|DIGIT/i, 'Health insurer', 'insurance'],
];

const BILL_WORD_RE = /\b(bill|premium|renewal|invoice|policy)\b/i;
const BILL_DUE_RE = /\bdue\b|payable by|renew (?:by|before|on)|(?:lapse|expire)s? on/i;
const BILL_PAID_RE = /\b(debited|received|successful(?:ly)?|paid|thank you|has been credited)\b/i;
const BILL_AMT_RE = new RegExp(
  String.raw`(?:bill (?:amount|amt)|amount (?:due|payable)|amt due|premium(?: amount| of| due)?|bill of|total due|due amount|renewal premium)\s*(?:of|is|:|-|for)?\s*(?:rs\.?|inr|₹)\s*` + NUM,
  'i',
);
const BILL_DATE_RE = /(?:due\s*(?:date|by|on)?|payable by|pay(?:ment)?\s*(?:by|before)|renew (?:by|before|on)|(?:lapse|expire)s? on)\s*(?:is|:|-)?\s*([0-9A-Za-z][0-9A-Za-z ,./-]{3,20})/i;
const EXPIRY_RE = /(?:plan|pack|validity|recharge|service|subscription|benefits?)[^.]{0,40}?(?:expir\w*|ends?|end on|valid till|valid upto|valid until|will end)\s*(?:on|by|:|-)?\s*([0-9A-Za-z][0-9A-Za-z ,./-]{3,20})/i;
const EXPIRY_PROMO_RE = /\b(offer|discount|cashback|% ?off|win|coupon|voucher|free trial|code)\b/i;
const FASTAG_BAL_RE = new RegExp(String.raw`(?:balance|bal)\.?\s*(?:is|:|-|of)?\s*(?:rs\.?|inr|₹)?\s*` + NUM, 'i');
const LOAN_OS_RE = new RegExp(String.raw`(?:principal outstanding|outstanding (?:principal|amount|balance)|loan balance|balance outstanding)[^.]{0,60}?(?:is|:|-|of|as)\s*(?:rs\.?|inr|₹)\s*` + NUM, 'i');

function billerFor(sender: string, body: string): { name: string; kind: BillKind } {
  const code = SENDER_RE.exec(sender.trim())?.[1] ?? sender;
  for (const [re, name, kind] of BILLERS) if (re.test(code)) return { name, kind };
  for (const [re, name, kind] of BILLERS) if (re.test(body)) return { name, kind };
  const kind: BillKind = /electric|power|discom/i.test(body)
    ? 'electricity'
    : /\bgas\b|lpg|png/i.test(body)
      ? 'gas'
      : /water|jal/i.test(body)
        ? 'water'
        : /insurance|policy|premium/i.test(body)
          ? 'insurance'
          : /broadband|fib(?:er|re)|internet|postpaid|mobile/i.test(body)
            ? 'phone & internet'
            : /dth|set ?top/i.test(body)
              ? 'tv'
              : 'other';
  return { name: code.toUpperCase(), kind };
}

const FAILED_RE = /\b(failed|declined|unsuccessful|not dispensed|could not be (?:processed|completed)|timed? ?out)\b/i;
const MONEY_TAKEN_RE = /debited|deducted|will be (?:reversed|refunded|credited back)|auto[- ]?revers|reversal (?:is |will be )?(?:initiated|processed within)|refund will/i;
/** "Rs 500 credited/refunded as reversal of your failed txn": the money came back. */
const REVERSAL_CREDIT_RE = /\b(credited|refunded|reversed)\b(?!.{0,20}\bwithin\b)/i;
const FUTURE_RE = /will be (?:credited|refunded|reversed)/i;

/** Pulls the bank's own helpline out of an alert ("…call 18002586161"), so we never hard-code one. */
export function helplineFrom(body: string): string | null {
  const m = /(?:call|contact|dial|reach us|helpline|customer care)\D{0,18}(1800(?:[\s-]?\d){4,7}(?!\d)|1860[\s-]?\d{3}[\s-]?\d{4}|\+?91[\s-]?\d{10}|\b[6-9]\d{9}\b|\b0\d{2,4}[\s-]?\d{6,8}\b)/i.exec(body);
  return m ? m[1].replace(/[\s-]/g, '') : null;
}

// Commercial sender IDs look like "AX-HDFCBK", "VM-SBIINB-S", "JD-ICICIT-T".
const SENDER_RE = /^[A-Z0-9]{2}-([A-Z0-9]{3,9})(?:-[A-Z])?$/i;

const BANKS: [RegExp, string][] = [
  [/HDFC/i, 'HDFC Bank'],
  [/ICICI/i, 'ICICI Bank'],
  [/SBI|CBSSBI/i, 'SBI'],
  [/AXIS/i, 'Axis Bank'],
  [/KOTAK/i, 'Kotak Bank'],
  [/YESB/i, 'Yes Bank'],
  [/IDFC/i, 'IDFC First Bank'],
  [/INDUS/i, 'IndusInd Bank'],
  [/PNB/i, 'PNB'],
  [/BOIIND|BANK ?OF ?INDIA/i, 'Bank of India'],
  [/BOB|BARODA/i, 'Bank of Baroda'],
  [/CANBNK|CANARA/i, 'Canara Bank'],
  [/UNIONB|UNION BANK/i, 'Union Bank'],
  [/AUBANK|AU BANK/i, 'AU Bank'],
  [/FEDBNK|FEDERAL/i, 'Federal Bank'],
  [/SCBANK|STANDARD CHARTERED/i, 'Standard Chartered'],
  [/AMEX/i, 'Amex'],
  [/ONECRD|ONECARD/i, 'OneCard'],
  [/PAYTM/i, 'Paytm Payments Bank'],
  [/AIRTEL/i, 'Airtel Payments Bank'],
  [/IDBI/i, 'IDBI Bank'],
  [/RBL/i, 'RBL Bank'],
];

const MF_SENDERS = /CAMS|KFIN|KARVY|MFCENTRAL|MFUTIL|BSESTAR|NSEMF/i;

const CUR = String.raw`(?:rs\.?|inr|₹)\s*`;
const AMOUNT_RE = new RegExp(CUR + NUM, 'i');
const AMOUNT_FALLBACK_RE = new RegExp(String.raw`(?:debited|credited|withdrawn)\s*(?:by|with|for|of)\s*` + NUM, 'i');
const BALANCE_RE = new RegExp(
  String.raw`(?:avl\.?|available|avail\.?|a\/c|clear|closing|total)\s*(?:bal(?:ance)?\.?)\s*(?:is|:|-|of)?\s*(?:rs\.?|inr|₹)?\s*` + NUM,
  'i',
);
const LIMIT_RE = new RegExp(
  String.raw`(?:avl\.?|available|avail\.?)\s*(?:credit\s*)?(?:lmt|limit)\.?\s*(?:is|:|-|of)?\s*(?:rs\.?|inr|₹)?\s*` + NUM,
  'i',
);
const DUE_RE = new RegExp(String.raw`(?:total|tot\.?)\s*(?:amount|amt\.?)?\s*due\s*(?:is|:|-|of)?\s*(?:rs\.?|inr|₹)?\s*` + NUM, 'i');
const MIN_DUE_RE = new RegExp(String.raw`min(?:imum)?\.?\s*(?:amount|amt\.?)?\s*due\s*(?:is|:|-|of)?\s*(?:rs\.?|inr|₹)?\s*` + NUM, 'i');
const DUE_DATE_RE = /(?:pay(?:ment)?\s*(?:by|before|on or before)|due\s*(?:date|by|on)|payable by)\s*:?\s*(?:is\s*)?([0-9A-Za-z][0-9A-Za-z ,./-]{3,20})/i;
const FROM_ACCT_RE = /(?:debited from|deducted from|from your|from)\s+(?:your\s+)?(?:\w+\s+bank\s+)?(?:a\/c|acct|account)\s*(?:no\.?)?\s*[:\s]*[x*.\s]*(\d{3,6})\b/i;
const LAST4_RE = /(?:a\/c|acct|account|card|ac)\s*(?:no\.?|number)?\s*(?:ending\s*(?:with|in)?\s*)?[:\s]*[x*.\s]*(\d{3,6})\b/i;

const IGNORE_RE =
  /\b(otp|one[- ]time password|verification code|will be debited|is due|due on|due date|requested money|collect request|has requested|pre-?approved|apply now|loan offer|failed|declined|unsuccessful|not processed|mandate (?:created|registered))\b/i;

const DEBIT_RE = /\b(debited|spent|withdrawn|sent|paid|purchase|payment of|dr\.?)(?=\W|$)/i;
const CREDIT_RE = /\b(credited|received|deposited|refund(?:ed)?|reversed|reversal|cr\.?)(?=\W|$)/i;

export function parseAmount(s: string): number {
  return parseFloat(s.replace(/,/g, ''));
}

export function institutionFor(sender: string, body: string): string {
  const code = SENDER_RE.exec(sender.trim())?.[1] ?? sender;
  for (const [re, name] of BANKS) if (re.test(code)) return name;
  for (const [re, name] of BANKS) if (re.test(body)) return name;
  return code.toUpperCase();
}

/** True for alphanumeric business senders (banks, AMCs). Personal numbers are skipped for privacy. */
export function isBusinessSender(address: string): boolean {
  return SENDER_RE.test(address.trim()) || /^[A-Z]{6,9}$/i.test(address.trim());
}

function cleanMerchant(m: string): string {
  let s = m.trim().replace(/\s+/g, ' ');
  if (s.includes('@')) s = s.split('@')[0]; // UPI VPA -> handle
  s = s
    .replace(/^(?:vpa|upi)[\s:-]*/i, '')
    .replace(/\s+(?:USD|EUR|GBP|AED|SGD|AUD|CAD|JPY|CHF)\b.*$/i, '') // "STEAM USD 40.00 international"
    .replace(/\s+(?:international|intl)\b.*$/i, '')
    .replace(/[.\-*]+$/, '');
  if (/^\d+$/.test(s) || /^(a\/c|ac|acct|account|your|you|card|xx|the|self)\b/i.test(s)) return '';
  return s.slice(0, 40);
}

export function extractMerchant(body: string, direction: Direction): string {
  const stop = String.raw`(?=\s+on\b|\s+via\b|\s+ref|\s+upi|\s+avl|\s+txn|\s+using|\s+thru|\s+dt\b|\.(?:\s|$)|[,;(]|\s+-|$)`;
  const name = String.raw`([A-Za-z0-9&'.\-* /]{2,40}?)`;
  const patterns: RegExp[] = [
    /\bvpa\s*:?\s*([\w.\-]+@[\w]+)/i,
    /\b(?:to|at)\s+([\w.\-]+@[a-z]+)\b/i,
    new RegExp(String.raw`;\s*` + name + String.raw`\s+credited`, 'i'),
    new RegExp(String.raw`trf to\s+` + name + stop, 'i'),
    new RegExp(String.raw`\binfo:?\s*` + name + stop, 'i'),
    new RegExp(String.raw`\bat\s+` + name + stop, 'i'),
  ];
  if (direction === 'debit') patterns.push(new RegExp(String.raw`\b(?:to|towards)\s+` + name + stop, 'i'));
  else patterns.push(new RegExp(String.raw`\b(?:from|by)\s+` + name + stop, 'i'));
  // Card alerts: "... on 06-11-26 on NETFLIX.COM"
  patterns.push(new RegExp(String.raw`\bon\s+(?!\d|date\b)` + name + stop, 'i'));

  for (const re of patterns) {
    const m = re.exec(body);
    if (m) {
      const c = cleanMerchant(m[1]);
      if (c && !/^(neft|imps|rtgs|upi|transfer)$/i.test(c)) return c;
    }
  }
  return '';
}

function detectMode(b: string): string {
  if (/\bupi\b|vpa|@[a-z]{3,}/i.test(b)) return 'UPI';
  if (/\batm\b|cash withdrawal|withdrawn/i.test(b)) return 'ATM';
  if (/\bneft\b/i.test(b)) return 'NEFT';
  if (/\bimps\b/i.test(b)) return 'IMPS';
  if (/\brtgs\b/i.test(b)) return 'RTGS';
  if (/\bnach\b|\becs\b|auto[- ]?debit|autopay|standing instruction|\bsi\b|e-?mandate/i.test(b)) return 'AUTOPAY';
  if (/\bcard\b|\bpos\b/i.test(b)) return 'CARD';
  return 'OTHER';
}

function detectKind(b: string): AccountKind {
  if (/fastag/i.test(b)) return 'wallet';
  // Whichever is mentioned first, a bank account or a card, is the account the alert is about.
  const acc = b.search(/\b(?:a\/c|acct|account)\b/i);
  const crd = b.search(/\bcard\b/i);
  if (acc >= 0 && (crd < 0 || acc < crd)) return 'bank';
  if (/credit card|\bcc\b|avl\.?\s*(?:credit\s*)?(?:lmt|limit)|available (?:credit )?limit/i.test(b)) return 'credit_card';
  if (/\bcard\b/i.test(b) && !/debit card/i.test(b) && !/a\/c|acct|account/i.test(b)) return 'credit_card';
  return 'bank';
}

function parseMf(body: string): ParsedSms | null {
  const units = /([\d,]+\.\d+)\s*units/i.exec(body);
  if (!units) return null;
  const amount = AMOUNT_RE.exec(body);
  const nav = /NAV\s*(?:of|:|is|@)?\s*(?:rs\.?|inr|₹)?\s*([\d,]+\.\d+)/i.exec(body);
  const folio = /folio\s*(?:no\.?|number)?\s*:?\s*([\w/]+)/i.exec(body);
  const scheme =
    /(?:in|under|of|for|scheme:?)\s+([A-Z][A-Za-z0-9&()\s\-]+?(?:Fund|Plan|ETF|Scheme|FoF|Growth|IDCW)(?:\s*-\s*(?:Direct|Regular)[A-Za-z\s\-]*?)?)(?=\s*(?:[,.;]|is\b|has\b|at\b|for\b|folio|nav|with|-\s*folio|$))/i.exec(
      body,
    );
  const sell = /redempt|redeemed|switch[- ]?out|withdrawal|sold/i.test(body);
  const u = parseAmount(units[1]);
  const n = nav ? parseAmount(nav[1]) : 0;
  const a = amount ? parseAmount(amount[1]) : u * n;
  if (!a || !u) return null;
  return {
    type: 'mf',
    order: {
      scheme: scheme
        ? scheme[1].replace(/\s+/g, ' ').replace(/^folio\s+\S+\s+(?:under|in|of|for)\s+/i, '').trim()
        : 'Unknown scheme',
      folio: folio ? folio[1] : '',
      amount: sell ? -a : a,
      units: sell ? -u : u,
      nav: n || a / u,
    },
  };
}

export function parseSms(sms: RawSms): ParsedSms | null {
  const body = sms.body.replace(/\s+/g, ' ').trim();
  if (!isBusinessSender(sms.address)) return null;

  if (MF_SENDERS.test(sms.address) || /\bunits\b.*\bnav\b|\bnav\b.*\bunits\b/i.test(body)) {
    return parseMf(body);
  }

  const institution = institutionFor(sms.address, body);
  // "EMI for Loan A/c XX5566 debited from A/c XX4821": the money left 4821, not the loan account.
  const fromMatch = FROM_ACCT_RE.exec(body);
  const last4Match = fromMatch ?? LAST4_RE.exec(body);
  const last4 = last4Match ? last4Match[1].slice(-4) : '';

  // Loan statements: "Principal outstanding on your Home Loan a/c XX1234 is Rs 24,50,000"
  const os = LOAN_OS_RE.exec(body);
  if (os && /\bloan\b/i.test(body) && !/\bcard\b/i.test(body)) {
    const loanNo = /loan\s*(?:a\/c|acct|account|no\.?)\s*(?:no\.?)?\s*[:\s]*[x*.\s]*(\d{3,})/i.exec(body);
    return { type: 'loan', lender: institution, last4: loanNo ? loanNo[1].slice(-4) : last4, outstanding: parseAmount(os[1]) };
  }

  // FASTag balance updates (toll debits are handled below as wallet transactions).
  const isFastag = /fastag/i.test(body);
  if (isFastag && !DEBIT_RE.test(body) && !CREDIT_RE.test(body)) {
    const b = FASTAG_BAL_RE.exec(body);
    if (b) return { type: 'fastag', issuer: institution, balance: parseAmount(b[1]) };
  }

  // Prepaid validity: "Your Jio plan expires on 12-Nov-26"
  if (!/\bcard\b/i.test(body) && !EXPIRY_PROMO_RE.test(body) && !/\botp\b/i.test(body)) {
    const ex = EXPIRY_RE.exec(body);
    if (ex) {
      const when = parseDateText(ex[1], sms.date);
      if (when) return { type: 'expiry', service: billerFor(sms.address, body).name, expiresOn: when };
    }
  }

  // Bills and insurance renewals that are due (not payment confirmations, not card statements).
  if (BILL_WORD_RE.test(body) && BILL_DUE_RE.test(body) && !BILL_PAID_RE.test(body) && !/credit card|\bcard\b/i.test(body)) {
    const amt = BILL_AMT_RE.exec(body) ?? AMOUNT_RE.exec(body);
    if (amt) {
      const dd = BILL_DATE_RE.exec(body);
      const b = billerFor(sms.address, body);
      return { type: 'bill', biller: b.name, kind: b.kind, amount: parseAmount(amt[1]), dueDate: dd ? parseDateText(dd[1], sms.date) : null };
    }
  }

  // Card statement: "Total Amt Due Rs 12,345 ... due by"
  const due = DUE_RE.exec(body);
  if (due && /card/i.test(body) && !DEBIT_RE.test(body.replace(/payment/gi, ''))) {
    const min = MIN_DUE_RE.exec(body);
    const dd = DUE_DATE_RE.exec(body);
    return {
      type: 'card_due',
      institution,
      last4,
      amountDue: parseAmount(due[1]),
      minDue: min ? parseAmount(min[1]) : null,
      dueDate: dd ? parseDateText(dd[1], sms.date) : null,
    };
  }

  const failed = FAILED_RE.test(body);
  const reversalCredit = failed && REVERSAL_CREDIT_RE.test(body) && !FUTURE_RE.test(body);
  if (failed && !reversalCredit && MONEY_TAKEN_RE.test(body)) {
    const a = AMOUNT_RE.exec(body) ?? AMOUNT_FALLBACK_RE.exec(body);
    if (a && parseAmount(a[1]) > 0) {
      return { type: 'failed', institution, last4, amount: parseAmount(a[1]), mode: detectMode(body) };
    }
  }
  // A reversal credit mentions the failed payment, so it must not be thrown away with the other "failed" alerts.
  if (IGNORE_RE.test(reversalCredit ? body.replace(FAILED_RE, '') : body)) return null;

  const d = DEBIT_RE.exec(body);
  const c = CREDIT_RE.exec(body);
  let direction: Direction | null = null;
  if (/payment (?:of .{1,30} )?(?:has been |is )?received|received .{0,30}payment|thank you for (?:your |the )?payment/i.test(body)) direction = 'credit';
  else if (reversalCredit) direction = 'credit';
  else if (d && c) direction = d.index <= c.index ? 'debit' : 'credit';
  else if (d) direction = 'debit';
  else if (c) direction = 'credit';

  const bal = BALANCE_RE.exec(body);
  const lim = LIMIT_RE.exec(body);

  if (!direction) {
    if (bal && /balance|bal\b/i.test(body)) {
      return { type: 'balance', institution, last4, balance: parseAmount(bal[1]) };
    }
    return null;
  }

  const amt = AMOUNT_RE.exec(body) ?? AMOUNT_FALLBACK_RE.exec(body);
  if (!amt) return null;
  const amount = parseAmount(amt[1]);
  if (!(amount > 0)) return null;

  const kind = detectKind(body);
  return {
    type: 'txn',
    amount,
    direction,
    institution,
    accountKind: kind,
    last4,
    merchant: extractMerchant(body, direction),
    mode: detectMode(body),
    balance: bal && kind !== 'credit_card' ? parseAmount(bal[1]) : null,
    availableLimit: lim ? parseAmount(lim[1]) : null,
  };
}

const PROMO_RE =
  /\b(offer|win|won|discount|% ?off|upto|up to|apply|eligible|pre-?approved|congratulations|voucher|coupon|limit (?:increase|enhance)|reward points?|instant loan|emi option|convert to emi|insurance cover|kyc)\b/i;
const FIN_WORD_RE = /\b(debit(?:ed)?|credit(?:ed)?|spent|withdrawn|sent|paid|received|txn|transaction|transferred|deposited|purchase|a\/c|acct|account|card)\b/i;

/**
 * True for a business SMS that looks like a real transaction alert (amount + account/transaction words,
 * not an OTP or promotion). Used to list alerts the parser could not read, so they can be supported.
 */
export function looksLikeTransactionAlert(sms: RawSms): boolean {
  if (!isBusinessSender(sms.address)) return false;
  const body = sms.body.replace(/\s+/g, ' ');
  if (!AMOUNT_RE.test(body) && !AMOUNT_FALLBACK_RE.test(body)) return false;
  if (!FIN_WORD_RE.test(body)) return false;
  return !IGNORE_RE.test(body) && !PROMO_RE.test(body);
}

/** Hides account, reference and phone numbers before an alert is shared. */
export function maskSms(body: string): string {
  return body
    .replace(/\d{6,}/g, (m) => 'X'.repeat(m.length - 2) + m.slice(-2));
}
