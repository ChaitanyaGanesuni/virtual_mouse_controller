import type { Direction } from './types';

/** Categories that are not real spending (money just moved between your own pots). */
export const NON_SPEND = new Set(['Self Transfer', 'Card Bill Payment', 'Investments', 'Refund', 'Reversed']);
/** Discretionary categories: where "waste" usually hides. */
export const DISCRETIONARY = new Set([
  'Food Delivery',
  'Dining Out',
  'Shopping',
  'Entertainment',
  'Subscriptions',
  'Travel',
  'Cabs',
]);

type Rule = [RegExp, string];

// Order matters: first match wins.
const DEBIT_RULES: Rule[] = [
  [/late (?:payment )?fee|penalty|finance charge|interest charge|annual fee|joining fee|over ?limit|bounce|return charge|min(?:imum)? bal|non[- ]maint|sms charge|gst on|service charge|convenience fee|surcharge|\bcharges?\b/i, 'Fees & Charges'],
  [/credit card (?:bill|payment)|card ?payment|cc ?payment|\bcred\b|billdesk.*card|bbps.*card|towards your card/i, 'Card Bill Payment'],
  [/mutual fund|\bsip\b|\bmf\b|zerodha|groww|upstox|angel ?one|kuvera|paytm ?money|\bcoin\b|indmoney|\bbse ?star|nse ?clearing|iccl|\bcams\b|kfin|\bnps\b|ppf|smallcase|dhan\b|5paisa|icicidirect|hdfc ?sec/i, 'Investments'],
  [/swiggy(?!.*instamart)|zomato|eatsure|box8|faasos|dunzo daily/i, 'Food Delivery'],
  [/instamart|blinkit|zepto|bigbasket|bb ?now|dmart|jiomart|grofers|more retail|reliance fresh|spencer|nature'?s basket|kirana|grocer|supermarket|milk|dairy/i, 'Groceries'],
  [/restaurant|cafe|caf[eé]|starbucks|domino|mc ?donald|kfc|pizza|burger|subway|chaayos|haldiram|barbeque|dine|bar &|pub\b|bakery|biryani/i, 'Dining Out'],
  [/netflix|hotstar|disney|prime ?video|amazon ?prime|spotify|youtube ?premium|google ?(?:one|play|storage)|apple\.com|itunes|icloud|jio ?cinema|sonyliv|zee5|gaana|wynk|audible|linkedin|chatgpt|openai|anthropic|claude|notion|canva|adobe|microsoft|playstation|xbox|steam|tinder|bumble|cult\.?fit|gym/i, 'Subscriptions'],
  [/uber|ola\b|olacabs|rapido|blusmart|namma yatri|meru/i, 'Cabs'],
  [/petrol|diesel|fuel|hpcl|bpcl|iocl|indian ?oil|bharat ?petroleum|hp ?pay|shell\b|fastag|parking|metro|irctc|redbus|ksrtc|msrtc/i, 'Transport'],
  [/makemytrip|goibibo|cleartrip|yatra|ixigo|indigo|air ?india|vistara|akasa|spicejet|oyo|airbnb|booking\.com|agoda|hotel|resort|easemytrip/i, 'Travel'],
  [/amazon|flipkart|myntra|ajio|meesho|nykaa|tata ?cliq|croma|reliance digital|decathlon|ikea|lenskart|firstcry|snapdeal|shoppers stop|lifestyle|westside|zara|h&m|uniqlo|mall/i, 'Shopping'],
  [/bookmyshow|pvr|inox|cinepolis|district|paytm insider|game|dream ?11|mpl\b|my11circle|rummy|poker/i, 'Entertainment'],
  [/electricity|bescom|msedcl|tneb|tata power|adani (?:electricity|gas)|bses|torrent power|water bill|\bgas\b|indane|hp gas|bharat gas|broadband|act fibernet|airtel|jio\b|vodafone|\bvi\b|bsnl|recharge|dth|tata ?play|postpaid|prepaid/i, 'Bills & Utilities'],
  [/\brent\b|nobroker|housing\.com|society|maintenance|landlord/i, 'Rent & Housing'],
  [/\bemi\b|loan|bajaj ?fin|home ?credit|nach|ecs/i, 'EMI & Loans'],
  [/insurance|\blic\b|premium|policybazaar|acko|digit ?insurance|hdfc ?ergo|star health|max life|tata aia/i, 'Insurance'],
  [/pharma|apollo|medplus|1mg|netmeds|pharmeasy|hospital|clinic|diagnostic|lab\b|doctor|practo|health/i, 'Health'],
  [/school|college|university|tuition|course|udemy|coursera|byju|unacademy|education|fees? for/i, 'Education'],
  [/atm|cash withdrawal|withdrawn/i, 'Cash Withdrawal'],
  [/\bself\b|own account/i, 'Self Transfer'],
];

const CREDIT_RULES: Rule[] = [
  [/refund|reversal|reversed|cashback|chargeback/i, 'Refund'],
  [/salary|\bsal\b|payroll|stipend/i, 'Salary'],
  [/\binterest\b|int\.? ?(?:pd|cr)\b|\bint\b.*credit|dividend|\bdiv\b/i, 'Interest & Dividends'],
  [/redemption|redeem|zerodha|groww|upstox|nse ?clearing|iccl|mutual fund/i, 'Investments'],
  [/payment received|thank you for (?:the )?payment|payment of .* (?:has been )?received/i, 'Card Bill Payment'],
  [/self|own account/i, 'Self Transfer'],
];

export interface UserRule {
  pattern: string; // lower-case substring of merchant
  category: string;
}

export function categorize(
  merchant: string,
  body: string,
  direction: Direction,
  mode: string,
  userRules: UserRule[] = [],
): string {
  const m = merchant.toLowerCase();
  for (const r of userRules) if (m && m.includes(r.pattern)) return r.category;

  const rules = direction === 'debit' ? DEBIT_RULES : CREDIT_RULES;
  // Merchant name is the strongest signal, then the whole SMS text.
  for (const [re, cat] of rules) if (merchant && re.test(merchant)) return cat;
  for (const [re, cat] of rules) if (re.test(body)) return cat;

  if (direction === 'credit') return 'Income';
  if (mode === 'ATM') return 'Cash Withdrawal';
  if (mode === 'UPI') return 'UPI Payments (Other)';
  return 'Other';
}

export const ALL_CATEGORIES = [
  ...new Set([...DEBIT_RULES.map((r) => r[1]), ...CREDIT_RULES.map((r) => r[1]), 'Income', 'UPI Payments (Other)', 'Other']),
].sort();
