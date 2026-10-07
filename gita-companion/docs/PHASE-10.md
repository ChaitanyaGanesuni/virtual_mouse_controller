# Phase 10 report: Testing and optimisation

Exit criterion: *release checklist green.* **Everything that can be checked automatically is green.**

[RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md) lists every item. The ones left need you or a real phone:

- signing with your own key (5 minutes; see [RELEASE.md](RELEASE.md));
- deploying the server;
- a profile run, a TalkBack walk-through and a compression check on a phone;
- a fluent reader's review of the Telugu text.

## Performance

Measured on the CI machine. A mid-range phone is roughly 3–5× slower, so the
test budgets are set at a phone target divided by four.

| What the user waits for | Measured |
|---|---|
| First install (copies the 4.2 MB content pack once) | 0.15–0.5 s |
| Later starts: check the installed pack | ~3 ms |
| Open the content repository | ~15–20 ms |
| Open a verse (p95) / a chapter (max) | 0.25 ms / 1.7 ms |
| First search (loads the concept index) | ~40 ms |
| Question search, p50 / p95 over the 86 golden questions | 1.8 / 6–7 ms |
| Search while typing (p95) | 2–4 ms |
| Chapter playlist (largest) | ~4 ms |
| My Gita with 701 verses read and 600 cards: progress / due cards / grade a card | 9 / 3 / 5 ms |

**Change made:** Android's audio service was started *before* the first
frame; it now starts right after, so it never delays opening the app.

**Scrolling.** The deterministic check is how many widgets are rebuilt per
frame while scrolling:

| Screen | Rebuilt per frame |
|---|---|
| Chapter 18 (78 verses) | 55 |
| Reader at the largest text size | 22 |
| Search results | 40 |

These show the lists build only the rows coming into view. A list that stopped being lazy would fail the test at once. Debug-mode frame times are printed but not judged: they vary 2× between CI runs, and judging them broke CI once, as recorded below. Smoothness on a real phone is a checklist item.

**APK size** (release, obfuscated):

| APK | Size |
|---|---|
| arm64-v8a (most phones) | 25.5 MB |
| armeabi-v7a (older phones) | 22.9 MB |
| x86_64 | 27.0 MB |
| Universal | 64 MB |

Share the per-device APKs, or let the Play Store pick, using an App Bundle.

## Accessibility audit

`test/accessibility_test.dart` covers 11 screens: Home, chapters, a chapter, the reader, search, My Gita, revision, Daily Practice, Downloads, Settings and the teacher. On each screen, in the light and the dark theme, it checks that:

- every tap target is at least 48×48 dp;
- every tap target has a label TalkBack can read;
- text contrast meets WCAG AA.

All 22 screen-and-theme runs pass.

**Large text.** At the largest system text size (200%), in the English and Telugu UI, two screens overflowed. Both are fixed:

- the reader's *Previous / Next* bar now shortens its labels;
- the chapter's "About N minutes to listen" line now wraps.

## Security review

| Area | Finding | Action |
|---|---|---|
| Dependencies | Server packages clean. pip/setuptools in the base image had advisories. | `pip-audit` runs in CI and fails the build on any known vulnerability. pip and setuptools are upgraded in the image. |
| Secrets | None in the repository. Keystores and `key.properties` are git-ignored. | The CI test key's password is masked in logs. |
| HTTP | No security headers. API responses could have been cached by intermediaries. | Added nosniff, no-referrer, DENY framing, HSTS, and `no-store` on API responses. Public pack files keep their own caching. |
| Request size | Only sync checked its size. | A global 1 MB limit (sync 4 MB), also enforced for bodies sent without a length. |
| Android network | Release builds allowed plain HTTP to localhost and the emulator host. | That exception now exists only in debug builds, in both the network config and the app's own address check. |
| Android backup | `allowBackup=false` already. On Android 12+, device-to-device transfer needed its own rule. | Added `data_extraction_rules.xml`: nothing is copied by cloud backup or device transfer. |
| Code | Dart code was readable in the APK. | Release builds are obfuscated, and symbols are kept as a CI artifact. |

Already in place from earlier phases and re-checked:

- accounts: no personal data, rotating refresh tokens with reuse detection, tokens in the Android Keystore, and `alg=none` and forged tokens rejected (tested);
- AI answers: may cite only verses they were given;
- rate limits on sign-up, recovery, sync and downloads;
- notes and journal encrypted at rest and bound to their account;
- only catalogued files are served for download;
- the server runs as a non-root user in Docker;
- the API docs are hidden in production.

## Costs

Measured in CI (`tests/test_costs.py`). Token counts use a deliberately high estimate, because the tokenizer could not be downloaded in CI's sandbox. Once the server is deployed, `python -m workers.usage_report` prints the real counts stored with every answer.

| Item | Measured |
|---|---|
| Prompt for a free question (p50 / p95), English and Telugu | ~1,410 / ~1,470 tokens |
| Prompt for "explain this verse" | ~1,090 tokens |
| One question in total, with a typical answer (~450 tokens; capped at 1,400) | ~1,900 tokens |
| Database space for a heavy user (a year of daily use: everything read, 200 notes, 300 cards, 365 journal entries) | ~615 kB |
| First full sync for that user, upload / download (before gzip) | ~350 / ~320 kB |
| Content update | 4.2 MB, only when content changes |
| Chapter audio for offline listening | made on the phone: no server cost |

What that means on the free tiers. Check each provider's current limits; they change.

- **Groq.** About 1,900 tokens per question. The server stays inside its own daily request budget (`llm.yaml`, 500 per provider) and each person's limit (30 questions a day). Answers to "explain this verse" in each mode are cached and shared by everyone, so popular verses cost nothing after the first time. Gemini and OpenRouter are configured as fallbacks.
- **Neon (0.5 GB).** Content and the app's tables take about 12–18 MB. That leaves room for about 800 heavy users, or many thousands of typical ones.
- **Render (free web service).** It sleeps after inactivity. The first request after a pause takes up to a minute, and the app's timeouts allow for that. Bandwidth per user is small: sync is a few hundred kB once, then changes only. Content updates are 4.2 MB each.

## Release build

- **Signing.** From `android/key.properties` locally, or from four GitHub secrets in CI ([RELEASE.md](RELEASE.md)). Without them, CI signs with a throwaway key, so every run proves the signing path. Each APK's signature is verified, and the certificate is printed in the log.
- **Speech compression.** Device speech (WAV, ~48 kB/s) is converted to AAC (~5 kB/s) with Android's built-in encoder, so a chapter downloaded for offline use takes about a ninth of the space. If the phone's encoder fails, the WAV is kept and playback is unaffected. The Kotlin compiles in CI and the Dart side is tested; the encoder itself still needs a check on a real phone (checklist).

## Problems found and fixed

- **Two layouts overflowed at 200% text** (reader navigation bar, chapter stats). Both now shrink or wrap.
- **Release builds trusted plain HTTP to local addresses.** That is now debug-only.
- **Chunked request bodies.** Without a declared length, an over-limit body got a 400 instead of 413, because FastAPI swallowed the error. Such bodies are now buffered up to the limit and replayed.
- **Kotlin operator precedence** (`flags and X != 0`) was caught by reading the code, before CI compiled it.
- **The first frame-time budget failed once on CI** (66 ms against 60 ms) because of timing noise. Frame time is now reported, not judged; the rebuild count is the real check.
- **Newer `apksigner` versions label certificates differently**, so the CI step that prints the signer now matches both forms.
- **A vector-search test failed once in CI** with no rows. The HNSW index is approximate, and rows other tests had rolled back were still in its graph. The test now does an exact scan. The app's own vector search now uses pgvector's iterative scans, so its model filter can no longer leave it short of results.

## Limitations

1. **Measured on CI, not on phones.** The benchmarks and frame checks catch regressions, but they are not phone timings. Real numbers come from the 👤 profile run.
2. **Token counts are estimates** until the server runs. The usage report then gives exact figures.
3. **The universal APK is 64 MB.** Use the per-device APKs (23–26 MB) or an App Bundle on the Play Store.
4. **`flutter_tts` uses the old Kotlin Gradle plugin.** Flutter warns that future versions will need a plugin update. Nothing breaks today; watch for a new `flutter_tts` release.
