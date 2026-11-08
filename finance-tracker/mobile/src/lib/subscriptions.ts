import type { Recurring } from './analysis';
import { nextMonthly } from './forecast';

export interface ServiceInfo {
  name: string;
  steps: string[];
  url?: string;
}

/**
 * How to cancel common subscriptions in India. Only long-stable account URLs are linked;
 * everything else is step-by-step, since in-app menus change.
 */
const SERVICES: [RegExp, ServiceInfo][] = [
  [/netflix/i, { name: 'Netflix', url: 'https://www.netflix.com/cancelplan', steps: ['Open netflix.com/cancelplan (or Account → Cancel membership).', 'Confirm. You keep access until the end of the billing period.'] }],
  [/spotify/i, { name: 'Spotify', url: 'https://www.spotify.com/account/', steps: ['Open spotify.com/account in a browser (not the app).', 'Your plan → Change plan → Cancel Premium.'] }],
  [/youtube|google ?youtube/i, { name: 'YouTube Premium', url: 'https://www.youtube.com/paid_memberships', steps: ['Open youtube.com/paid_memberships.', 'Manage membership → Deactivate.'] }],
  [/google ?play|google ?one|google ?storage|google\b/i, { name: 'Google Play / Google One', url: 'https://play.google.com/store/account/subscriptions', steps: ['Open Play Store → profile → Payments & subscriptions → Subscriptions.', 'Pick the subscription → Cancel.'] }],
  [/apple\.com|itunes|icloud|apple/i, { name: 'Apple', steps: ['iPhone: Settings → your name → Subscriptions.', 'Pick the subscription → Cancel.'] }],
  [/prime|amazon/i, { name: 'Amazon Prime', steps: ['Amazon app → Account → Prime → Manage membership.', 'End membership (refunds may apply if benefits unused).'] }],
  [/hotstar|disney|jio ?cinema|jiohotstar/i, { name: 'JioHotstar', steps: ['App or website → My Space/Profile → Subscription.', 'Cancel auto-renew. If paid by UPI Autopay, also revoke the mandate (below).'] }],
  [/sony ?liv/i, { name: 'SonyLIV', steps: ['Account → My Subscription → Cancel auto-renewal.'] }],
  [/zee5/i, { name: 'ZEE5', steps: ['Profile → My Subscription → Cancel renewal.'] }],
  [/swiggy ?one/i, { name: 'Swiggy One', steps: ['Swiggy → Account → Swiggy One → Manage → Cancel.'] }],
  [/zomato/i, { name: 'Zomato Gold', steps: ['Zomato → Profile → Gold → Manage membership → Cancel auto-renew.'] }],
  [/cult\.?fit|cultfit|curefit/i, { name: 'cult.fit', steps: ['cult app → Profile → Memberships → pick the pack → Pause or cancel auto-renew.'] }],
  [/linkedin/i, { name: 'LinkedIn Premium', steps: ['LinkedIn → Me → Premium features → Manage → Cancel subscription.'] }],
  [/audible/i, { name: 'Audible', steps: ['audible.in on a browser → Account details → Cancel membership.'] }],
  [/openai|chatgpt/i, { name: 'ChatGPT', steps: ['ChatGPT → Settings → Subscription → Manage → Cancel plan.'] }],
  [/adobe/i, { name: 'Adobe', steps: ['account.adobe.com → Plans → Manage plan → Cancel. Annual plans paid monthly may charge an early-cancellation fee.'] }],
  [/microsoft|office ?365|xbox/i, { name: 'Microsoft', steps: ['account.microsoft.com → Services & subscriptions → Manage → Cancel.'] }],
  [/times ?prime/i, { name: 'Times Prime', steps: ['Times Prime app → Account → Membership → Turn off auto-renew.'] }],
  [/tinder|bumble|hinge/i, { name: 'Dating app', steps: ['Cancel in the Play Store (Payments & subscriptions → Subscriptions); deleting the app does not cancel it.'] }],
];

/** Applies to everything charged by UPI Autopay or a card standing instruction. */
export const GENERIC_STEPS = [
  'UPI Autopay: open the UPI app you pay with (GPay, PhonePe, Paytm, bank app) → Autopay / Mandates → pick the merchant → Cancel or Pause.',
  'Card: ask your bank to cancel the "standing instruction" (e-mandate) for this merchant in its app or on the helpline.',
  'Cancelling in the service stops renewal; revoking the mandate stops the money. Do both if you can.',
];

export function serviceFor(merchant: string): ServiceInfo | null {
  for (const [re, info] of SERVICES) if (re.test(merchant)) return info;
  return null;
}

export type SubStatus = 'unreviewed' | 'keep' | 'cancelled';

export interface SubState {
  status: SubStatus;
  at: number;
}

export interface SubscriptionView extends Recurring {
  id: string; // normalised merchant
  service: ServiceInfo | null;
  status: SubStatus;
  yearlyCost: number;
  nextDue: number;
  /** Marked cancelled, but charged again afterwards: worth chasing a refund. */
  chargedAfterCancel: boolean;
}

export const subId = (merchant: string) => merchant.toLowerCase().replace(/[^a-z0-9]/g, '');

export function subscriptionViews(recurring: Recurring[], states: Record<string, SubState>, lastChargeOf: (id: string) => number): SubscriptionView[] {
  return recurring
    .filter((r) => ['Subscriptions', 'Entertainment', 'Other', 'UPI Payments (Other)', 'Shopping', 'Health', 'Education'].includes(r.category) || serviceFor(r.merchant))
    .map((r) => {
      const id = subId(r.merchant);
      const st = states[id];
      const last = lastChargeOf(id) || r.lastCharged;
      return {
        ...r,
        id,
        service: serviceFor(r.merchant),
        status: st?.status ?? 'unreviewed',
        yearlyCost: r.periodDays === 30 ? r.amount * 12 : r.periodDays === 365 ? r.amount : (r.amount * 365) / r.periodDays,
        nextDue: r.periodDays === 30 ? nextMonthly(r.lastCharged) : r.lastCharged + r.periodDays * 86_400_000,
        chargedAfterCancel: st?.status === 'cancelled' && last > st.at + 2 * 86_400_000,
      };
    })
    .sort((a, b) => Number(b.chargedAfterCancel) - Number(a.chargedAfterCancel) || b.yearlyCost - a.yearlyCost);
}
