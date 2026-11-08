# Paisa Watch

An Android app that tracks your money **without you typing anything in**. It reads the alert SMS your banks,
credit-card issuers, UPI apps and mutual-fund registrars (CAMS / KFintech) already send you, and turns them into:

- **Spending**: every debit categorised (food delivery, groceries, rent, subscriptions, cabs, fees…), month by month,
  with top merchants. Self-transfers and card-bill payments are detected so nothing is counted twice.
- **Money leaks**: bank and card fees and penalties, credit-card interest, recurring subscriptions, food-delivery
  habits, small impulse buys, real-money gaming, category spikes, and untracked cash. Each comes with an estimated
  monthly saving.
- **Balances & net worth**: latest balance for each bank account (from "Avl Bal" in alerts), card dues (statement
  amount minus payments since), due dates, remaining limit, and investments.
- **Real-time alerts**: a notification the moment a bank charge or penalty, card bill, recurring subscription charge
  or large payment hits, even when the app is closed. Choose "Important only", "Every transaction" or "Off".
- **Bill reminders**: 3 days before, the day before and on the due date of every unpaid card bill. Reminders are
  re-armed after a phone restart and stop once the bill is paid.
- **Unread alerts**: bank messages that look like transactions but couldn't be read are listed in Settings, and can
  be shared with long numbers masked so support can be added.
- **Budgets**: a monthly limit per category (smart suggestions from your last 3 months) with progress rings,
  plus an overall limit tracked in real time. Alerts fire at 80% and 100%.
- **Month-end forecast**: likely spend by month end (spent so far + bills still due + your usual daily rate),
  and how much you'll have left after spending and investing.
- **Net-worth trend**: month-end net worth rebuilt from SMS balances, card statements and fund purchases.
- **Money Health score** (0–100): savings rate, fees, emergency cushion, investing habit and fund costs.
  Parts that can't be measured yet (e.g. no salary SMS) are left out instead of counted as zero.
- **Protection**: failed payments ("debited but failed") tracked against RBI refund deadlines (T+1 for UPI/IMPS,
  T+5 for cards/ATM) with the ₹100/day compensation owed if late; possible double charges, large first payments to new
  merchants, foreign-currency and late-night card use. Buttons call your bank's helpline (taken from its own SMS) or
  the national cybercrime helpline 1930.
- **Subscriptions**: every recurring charge with its yearly cost, a monthly "still using it?" review, step-by-step
  cancel guides (plus how to revoke UPI Autopay / card mandates), and a warning if it's charged after you cancelled.
- **Tax**: 80C / 80CCD(1B) / 80D / 80TTA found in your SMS for the financial year, with an honest note about the new
  regime; long-term equity gains you can still book tax-free (₹1.25L allowance, FIFO lots); rent receipts PDF for HRA.
- **Goals & weekly check-in**: savings goals that fill up as your net worth grows (on track / behind), and a Sunday
  evening summary of your week and the bills ahead.
- **Backup & restore**: your fixes, budgets, goals and settings to a file you keep; the app can also hide its
  content in recent apps (and block screenshots) while app lock is on.
- **App lock**: fingerprint, face or screen-lock PIN on open and after 30 seconds away.
- **Problem log**: errors are recorded on the phone only and can be shared (numbers masked).
- **Investments**: mutual-fund holdings built from allotment SMS, valued at live NAVs (mfapi.in / AMFI), with gain,
  XIRR and asset allocation.
- **How to invest better**: Regular-to-Direct plan switches (with the 10-year cost), idle cash beyond your
  emergency fund, card debt to clear first, savings rate, allocation drift from your target, concentration, too many
  overlapping funds, and long-term underperformers.

Everything runs on the phone. There is no server and no account. The only network call fetches public NAVs.

## Install

1. Copy `paisa-watch.apk` to your Android phone and open it. Allow "Install unknown apps" for your file manager
   or browser if Android asks.
2. Open **Paisa Watch**, tap **Allow SMS access & scan**, and allow SMS and notifications.
3. That's it. New alerts are picked up every time you open the app, and you can pull down to refresh.

Want to look around first? Tap **Explore with sample data**. You can switch it off in Settings.

If a transaction lands in the wrong category, tap it and pick the right one. The app remembers this for that
merchant from then on.

## Limitations

- **Android only.** iOS does not let apps read SMS.
- **Not on the Play Store as-is.** Google Play allows `READ_SMS` only for default SMS apps, so this build is meant for
  sideloading on your own phone.
- **Only what your bank texts you.** Make sure SMS alerts are on for every account and card. Most Indian banks send
  them by default. Some, such as Kotak and HDFC for small UPI payments, may only send email above a threshold.
- **Stocks, EPF and NPS values aren't sent by SMS.** The app tracks the money you send to brokers, NPS and PPF, but
  not their market value. Mutual funds are fully covered.
- The app keeps about 13 months of history (whatever is still in your SMS inbox).

### Going further: RBI Account Aggregator

To pull data straight from banks, demat accounts (NSDL/CDSL), EPF and NPS, the next step is RBI's
**Account Aggregator** network (for example through Setu or Finvu). Production access requires registering as a
Financial Information User (FIU) and running a small backend, so it isn't part of this standalone APK.

## Develop

```bash
cd mobile
npm install
npm test            # parser and analysis tests (Node)
npm run typecheck
PAISA_KEYSTORE=/path/paisa-watch-upload.jks PAISA_KEYSTORE_PASSWORD=... PAISA_KEY_ALIAS=paisa-upload \
  npm run build:apk # needs JDK 17 and the Android SDK (ANDROID_HOME)
```

Release builds are signed with your own upload key (`plugins/withReleaseSigning.js`) and refuse to build without it.
**Never commit the keystore, and never lose it:** Android only installs an update signed with the same key, so a lost
key means uninstalling the app (and its saved category fixes) to install a new version.

Project layout:

| Path | What |
|---|---|
| `mobile/modules/sms-reader` | Kotlin Expo module: reads the inbox (business senders like `AX-HDFCBK` only), the background SMS receiver for real-time alerts, and bill reminders (AlarmManager, re-armed on boot). |
| `mobile/src/lib/smsParser.ts` | Parses bank, card, UPI, statement and MF allotment SMS from all major Indian banks. |
| `mobile/src/lib/categorizer.ts` | Merchant and keyword categorisation rules. |
| `mobile/src/lib/ledger.ts` | Builds transactions, accounts and balances. Pairs self-transfers and card bill payments. |
| `mobile/src/lib/reminders.ts` | Plans card-bill reminders from statement due dates. |
| `mobile/src/lib/dates.ts` | Parses the date formats Indian banks use. |
| `mobile/src/lib/budgets.ts` | Budget suggestions, status and 80%/100% alerts. |
| `mobile/src/lib/forecast.ts` | Month-end spending and cash-left projection. |
| `mobile/src/lib/history.ts` | Month-end net-worth history rebuilt from SMS. |
| `mobile/src/lib/health.ts` | Money Health score. |
| `mobile/src/lib/guard.ts` | Failed-payment tracking (RBI TAT) and fraud signals. |
| `mobile/src/lib/subscriptions.ts` | Cancel guides and subscription review. |
| `mobile/src/lib/tax.ts`, `rent.ts` | Deductions, capital gains harvesting, rent receipts. |
| `mobile/src/lib/goals.ts`, `digest.ts` | Savings goals and the weekly check-in. |
| `mobile/src/lib/analysis.ts` | Monthly summaries, recurring-payment detection, waste insights. |
| `mobile/src/lib/investments.ts` | Holdings, live NAVs, XIRR, investment insights. |
| `mobile/src/screens/*` | Home, Spending, Leaks, Invest, Settings. |

The suggestions are rule-based general guidance, not advice from a SEBI-registered investment adviser.
