# Release checklist

✅ = checked automatically on every CI run; 👤 = needs a person or a real
phone, and says exactly what to do. The release is ready when every line
is ✅ or its 👤 step has been done.

## Correctness

| | Check | How |
|---|---|---|
| ✅ | Content: 701 verses, canonical counts, licence register, Sanskrit cross-check, dataset reproducible | content CI job |
| ✅ | Retrieval quality above its floors (English hit@8 0.914 / recall@8 0.594; Telugu 1.0 / 0.73) | `python -m gita_content.evaluate`, app golden-set test |
| ✅ | Server: 142 tests (accounts, tutor grounding and citations, sync, packs, security, costs) | backend CI job |
| ✅ | App: 258 tests, including the airplane-mode test and the reinstall/sync test | mobile CI job |
| ✅ | App and server agree on the sync format | shared fixture, tested on both sides |

## Performance

| | Check | Result |
|---|---|---|
| ✅ | Later app starts: verify the installed content | ~3 ms (first install copies the pack once: ~0.15–0.5 s) |
| ✅ | Audio service no longer delays the first frame | started after `runApp` |
| ✅ | Search: question p95 / while typing p95 | ~6 ms / ~3 ms on CI (budgets 40 / 25 ms) |
| ✅ | Lists stay lazy while scrolling (widgets rebuilt per frame) | chapter 55, reader 22, search 40 |
| 👤 | Smooth scrolling and start-up time on a real mid-range phone | `flutter run --profile` on the phone, open chapter 18 and the reader at the largest text size, scroll; the performance overlay should stay green. Note the cold-start time. |

## Accessibility

| | Check | Result |
|---|---|---|
| ✅ | Tap targets ≥ 48 dp, every target labelled, text contrast WCAG AA, on 11 screens in light and dark | `test/accessibility_test.dart` |
| ✅ | No overflow at 200% system text size, English and Telugu UI | same test |
| 👤 | TalkBack walk-through: Home → chapter → verse → listen → My Gita → revision | on a phone with TalkBack on; every control should be announced meaningfully |

## Security and privacy

| | Check | Result |
|---|---|---|
| ✅ | No known vulnerabilities in the server's Python dependencies | `pip-audit` in CI |
| ✅ | No secrets in the repository; keys only in server env / GitHub secrets | review + `.gitignore` for keystores |
| ✅ | HTTPS only in release builds; no cleartext exceptions | release `network_security_config.xml` |
| ✅ | Nothing leaves the phone through Android backup or device transfer | `allowBackup=false`, `data_extraction_rules.xml` |
| ✅ | Tokens in the Android Keystore; refresh tokens rotate and detect reuse | Phase 6 tests |
| ✅ | API responses not cacheable, security headers, request size limits | `tests/test_security.py` |
| ✅ | Notes and journal encrypted at rest; journal synced only by choice | Phase 8 tests |
| ✅ | Dart code obfuscated; symbols kept for crash reports | CI build flags and artifact |

## Release build

| | Check | Result |
|---|---|---|
| ✅ | APK builds, is signed, and the signature verifies | CI `apksigner verify` |
| ✅ | Per-device APKs: arm64 25.5 MB, armeabi-v7a 22.9 MB (universal 64 MB) | CI build log |
| 👤 | Signed with **your** release key | create it and add four GitHub secrets: [RELEASE.md](RELEASE.md). The CI log then says "Signed with: release key". |
| 👤 | AAC speech compression works on a phone | after installing, make a chapter available offline; *Downloads & storage* should show about 5 kB per second of speech, not 48 kB (it falls back to WAV safely if the phone's encoder fails) |

## Service

| | Check | How |
|---|---|---|
| 👤 | Server deployed (Render + Neon + Groq, all free) | [DEPLOY.md](DEPLOY.md), then set the `GITA_API_BASE_URL` repository variable |
| 👤 | AI explanations generated for the app (optional but recommended) | `gita-generate-ai` (backend README), then rebuild the content |
| 👤 | Watch real usage after launch | `python -m workers.usage_report` against the production database |
| 👤 | Telugu UI text and AI Telugu explanations reviewed by a fluent reader | the app labels them; review before a public launch |
