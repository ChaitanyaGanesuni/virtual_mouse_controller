# Phase 3 report: Basic mobile UI (Flutter shell + first APK)

## What was built

- **Flutter app** (`mobile/`, Flutter 3.47.5, Android): Riverpod for
  dependency injection, go_router, drift for the user database, `sqlite3`
  (bundled SQLite with FTS5) for the content pack.
- **Fully offline:** the content pack built by the pipeline is bundled as an
  asset and installed on first launch, named by content hash. A pack that
  is corrupt or doesn't match its manifest is replaced or rejected, and old
  packs are removed. The release manifest requests **no internet
  permission**.
- **Screens:**
  - Onboarding: app language, verse script, live preview.
  - Home: Today's verse, Continue learning, chapters strip, and a short
    "Coming next" list.
  - Chapters list and chapter overview with its verse list.
  - Basic verse page with previous/next.
  - Settings: theme, scripture text size, app language, verse script, IAST
    toggle, translation and explanation languages.
  - Sources & licences, and open-source licences.
- **Independent languages:** the UI language (English/Telugu) is separate
  from the verse script (Devanagari, Telugu script, IAST) and from the
  content languages.
- **Provenance in the UI:** every text block shows its source, an
  "AI-assisted" flag where relevant, and its review status. The corrected
  Phase 2 verses read "Corrected, awaiting scholarly review". 13.0 explains
  that it sits outside the 700. The English chapter glosses are labelled
  AI-assisted.
- **Today's verse:** deterministic per calendar date (the same verse on
  every device), drawn only from the 700 canonical verses.
- **Design:** paper-and-ink light theme, deep indigo dark theme, one
  saffron-gold accent, a line-drawn lotus as the only ornament, bundled
  Noto fonts, line height 1.85–1.9 for Indic scripts, adjustable scripture
  size, semantic headers.
- **CI:** a new `mobile` job builds the pack, runs code generation, checks
  formatting, analyzes, tests, builds the release APK and uploads it as the
  `gita-companion-apk` artifact.

## Tests

26 Flutter tests:

- Repository against the real pack: verse counts, three scripts,
  speakers, 13.0, reading order across chapters, verse of the day.
- Pack installer: install, read-only, FTS5 present, no re-copy, corrupt
  pack replaced, manifest and schema mismatches rejected.
- Settings persistence and database constraints.
- Widget flows: onboarding → home, home → verse, chapters → chapter →
  verse → next, invalid deep link, Telugu UI, settings persistence, and
  dark theme at maximum text size without overflow.

Content pipeline tests are now at 79.

## Problems found and fixed

1. The Android SDK host (dl.google.com) is blocked in this environment,
   so the APK cannot be built here. It is built by GitHub Actions instead.
   Everything else (analysis, tests, rendering) runs locally.
2. Rendering the screens with the real fonts showed that a long last
   half-verse wrapped its `॥` onto a line of its own. Dandas are now joined
   to the preceding word with a no-break space.
3. The same review showed that the mid-verse speaker heading in 1.28 looked
   like verse text. Speaker headings inside verses now use the speaker
   style.
4. The IAST font has no danda glyph; it now falls back to the Devanagari
   font explicitly.

## Known limitations

- No translations or explanations yet (Phase 2 open item: an English
  public-domain source must be imported). The verse page says so.
- Chapter summaries, themes and reading/listening times are Phase 4. They
  are not shown rather than invented.
- The release APK is signed with the debug key so it installs directly. A
  Play Store release needs a proper upload key.
- The Telugu UI strings were drafted with AI assistance and need review by
  a fluent reader.
