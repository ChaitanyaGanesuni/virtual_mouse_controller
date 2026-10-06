# Phase 8 report: My Gita

Exit criterion: *data survives reinstall when signed in.* **Met.**

| Where it is tested | What the test does |
|---|---|
| App (`mobile/test/sync_test.dart`) | One installation creates every kind of study data and syncs. The phone is "reset". A fresh installation enters the recovery code and gets everything back: bookmarks, favourites, notes, highlights, revision cards and their review history, reading progress and the journal. |
| Server (`backend/tests/test_sync.py`) | The same round trip over HTTP against the real server and database. It also checks that notes and journal entries are stored encrypted. |
| UI (`mobile/test/my_gita_test.dart`) | The whole flow on screen: turn sync on, get a recovery code, open a new installation, enter the code, and the bookmark is back. |

## What was built

### Study data on the phone (local-first)

New tables in the app's own database (schema v4, upgraded in place):

| What | How it works |
|---|---|
| **Bookmarks** | One per verse. |
| **Favourites** | One per verse. |
| **"I understand this"** | One per verse. |
| **"Revise"** | One per verse. Adds the verse to spaced revision. |
| **Notes** | Three kinds: note, question and reflection. A note can belong to a verse or stand alone. A question about a verse can be sent to the AI teacher. |
| **Highlights** | Select words in the translation and choose *Highlight*. Highlights are stored by the text's ID, which is the same in the app and on the server. |
| **Reading progress** | Opening a verse counts as reading it. Shown as "Chapter 2 · 7 of 72" and "Continue at Verse 3.19" on Home. |
| **Spaced revision** | Marking a verse *Revise* creates two cards: "What does this verse teach?" and, a day later, "How could you apply this verse today?". The user recalls, reveals the meaning, and grades the card: Again, Hard, Good or Easy. Cards come back after 1 → 2 → 4 → 7 → 14 → 30 … days. *Again* brings a card back in the same session. Every review is logged, and the scheduler sits behind an interface, so FSRS can replace the fixed intervals later without losing anything. |
| **Daily Practice** | Today's verse in five steps: Listen → Understand → Reflect → Apply → Journal. There are no streaks and nothing is lost by missing a day. Progress says *how much has been remembered for a week or more*, not how often buttons were pressed. |

Every change is written on the phone first, so all of it works offline.

### Sync and recovery

Sync is **off by default**. When it is on:

- **One request each way.** The app sends what changed since its last sync and receives what changed elsewhere, after a cursor.
- **When it runs.** At app start, when the app comes back to the foreground, when it goes to the background, and 20 seconds after changes.
- **Ordering.** The server stamps every write with a sequence number, maintained by a database trigger. Syncs of one account are serialised with a database lock. Together these mean no change can be skipped, even with two devices syncing at once.
- **Conflicts.** The later edit wins, judged by when it was made on the device. Times more than five minutes in the future are clamped to the server's clock, so a device with a wrong clock cannot win forever. A device whose older edit loses gets the winning version back straight away. Reading history merges instead: earliest first read, latest last read, highest count.
- **Deletions** are kept as tombstones, so other devices learn about them.

**Recovery code instead of email or Google sign-in.** Turning sync on offers a recovery code, for example `7KQ2-…` (24 characters, 120 random bits, shown once). The server stores only its hash. Entering the code on a new installation signs it in to the account; the data comes back and merges with anything already on the phone. A new code replaces the old one, and look-alike characters are accepted (O for 0, I or L for 1). This needs no personal data at all, in keeping with the anonymous accounts from Phase 6. Google or email sign-in can be added later on top of the same accounts.

**Privacy:**

- Note text and journal entries are **encrypted at rest** on the server with AES-256-GCM. Each value is bound to its account and field, so a stored value cannot be moved to another account or column.
- `DATA_ENCRYPTION_KEY` is required in production, and the Render blueprint generates it.
- **The journal never leaves the phone** unless the user turns on *Include my journal*. Turning that off erases the journal from the server and keeps the copy on the phone.
- An ID that belongs to another account is never updated or returned.
- Requests are limited per user and per network address, and capped in size.

### App and server agree, checked from both sides

The app test writes the exact request the app sends to `backend/tests/fixtures/sync_request_from_app.json`. The server tests send that file to the real server and require every item to be accepted, and every field the app reads to come back. Timestamps round-trip to the millisecond.

## Tests

| Part | Tests | New in Phase 8 |
|---|---|---|
| backend | 131 | 14 sync and recovery tests (round trip, conflicts, clock skew, deletions, paging, isolation between accounts, invalid references, merging, journal privacy, limits, encryption, the app contract) |
| mobile | 190 | Scheduler, repository, v3→v4 upgrade, sync client against a fake server with the server's rules (reinstall, two devices, paging, failures, account change), the app contract, and widget tests for the reader, My Gita, revision, Daily Practice and sync settings |

## Problems found and fixed

- **The database trigger overwrote the device's time.** The server's `updated_at` trigger sets the server's write time, so it could not decide conflicts. A separate `client_updated_at` column now does.
- **Row counts were unreliable.** SQLAlchemy reports -1 for `INSERT … ON CONFLICT`, so a rejected edit looked accepted. The server now checks whether `RETURNING` gave back a row.
- **Turning on journal sync did not upload the journal.** The re-sent rows were not newer than the server's copy. Toggling the journal now marks them as changed, strictly later than before.
- **A restored phone ignored the account's journal.** On a new installation journal sync starts off. Restoring now turns it on when the account has journals on the server.
- **Cancelling an update stream hung.** Cancelling drift's `async*` update stream never finished. A small shared helper (`core/db/watch.dart`) replaces it.
- **The restore dialog used its text controller after disposing it.** This crashed while the dialog was closing. The dialog now owns its controller.
- **A screen-reader check failed.** Progress bars must report numbers; they now do.
- **Tests scrolled the wrong list.** Selectable text has its own scroller, so tests now find the screen's main list explicitly.
- **Bookmarks on two devices could clash.** Bookmarks are now one row per verse on the server, so two devices bookmarking the same verse meet on the same row.

## Limitations and decisions for you

1. **Losing the recovery code means losing the synced copy.** Data on the phone itself is unaffected. There is no email reset by design. I can add Google sign-in if you want an easier route; it needs an OAuth client from your Google account.
2. **Sync needs the deployed server** ([DEPLOY.md](DEPLOY.md)). The new `DATA_ENCRYPTION_KEY` is generated by the Render blueprint. If you deploy another way, set it once and keep it: losing it makes the stored notes unreadable.
3. **Settings, AI teacher conversations and listening position are not synced yet.** They stay on each device. I can add them in Phase 9 if you want.
4. **Highlights work on the translation only**, not on the Sanskrit or the explanations.
5. **The new Telugu strings were drafted with AI assistance** and should be checked by a fluent reader, like the rest of the Telugu UI.
