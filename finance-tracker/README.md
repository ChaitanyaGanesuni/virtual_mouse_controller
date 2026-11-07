# Paisa Watch

An Android app that tracks your money **without you typing anything in**. It reads the alert SMS your banks,
credit-card issuers, UPI apps and mutual-fund registrars (CAMS / KFintech) already send you, and turns them into:

- **Spending**: every debit categorised (food delivery, groceries, rent, subscriptions, cabs, fees…), month by month,
  with top merchants. Self-transfers and card-bill payments are detected so nothing is counted twice.
- **Money leaks**: bank and card fees and penalties, credit-card interest, recurring subscriptions, food-delivery
  habits, small impulse buys, real-money gaming, category spikes, and untracked cash. Each comes with an estimated
  monthly saving.
- **Balances & net worth**: latest balance for each bank account (from "Avl Bal" in alerts), card dues and
  remaining limit, and investments.
- **Investments**: mutual-fund holdings built from allotment SMS, valued at live NAVs (mfapi.in / AMFI), with gain,
  XIRR and asset allocation.
- **How to invest better**: Regular-to-Direct plan switches (with the 10-year cost), idle cash beyond your
  emergency fund, card debt to clear first, savings rate, allocation drift from your target, concentration, too many
  overlapping funds, and long-term underperformers.

Everything runs on the phone. There is no server and no account. The only network call fetches public NAVs.

## Install

1. Copy `paisa-watch.apk` to your Android phone and open it. Allow "Install unknown apps" for your file manager
   or browser if Android asks.
2. Open **Paisa Watch** and tap **Allow SMS access & scan**.
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
npm run build:apk   # needs JDK 17+ and the Android SDK (ANDROID_HOME)
```

Project layout:

| Path | What |
|---|---|
| `mobile/modules/sms-reader` | Small Kotlin Expo module that reads the inbox. It only returns business senders like `AX-HDFCBK`. |
| `mobile/src/lib/smsParser.ts` | Parses bank, card, UPI, statement and MF allotment SMS from all major Indian banks. |
| `mobile/src/lib/categorizer.ts` | Merchant and keyword categorisation rules. |
| `mobile/src/lib/ledger.ts` | Builds transactions, accounts and balances. Pairs self-transfers and card bill payments. |
| `mobile/src/lib/analysis.ts` | Monthly summaries, recurring-payment detection, waste insights. |
| `mobile/src/lib/investments.ts` | Holdings, live NAVs, XIRR, investment insights. |
| `mobile/src/screens/*` | Home, Spending, Leaks, Invest, Settings. |

The suggestions are rule-based general guidance, not advice from a SEBI-registered investment adviser.
