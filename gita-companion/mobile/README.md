# Gita Companion: mobile app (Flutter)

Offline-first Android app (iOS-ready codebase). Scripture content comes from
the content pipeline's SQLite pack, bundled as an asset and installed on
first launch. Only the AI teacher uses the network (HTTPS to the server set
in Settings or built in with `--dart-define=API_BASE_URL=https://...`); its
tokens are kept in the Android Keystore.

```
lib/
  app/        bootstrap: providers (composition root), router, theme
  core/
    content/  domain models, ContentRepository, pack installer (SQLite)
    db/       user database (drift): settings now, study data later
    settings/ AppSettings + repository
  features/   home, chapters, reader, settings, onboarding
  shared/     verse rendering, provenance labels, lotus ornament
  l10n/       UI strings: app_en.arb, app_te.arb
```

## Develop

```bash
pip install -e ../content          # content pipeline (for the pack)
tool/sync_content.sh                # builds assets/content/ from content/data/gita.json
flutter pub get
dart run build_runner build         # drift code generation
flutter analyze && flutter test
flutter build apk --release         # needs the Android SDK
```

Design-review screenshots with the real fonts:

```bash
flutter test --tags screenshots --run-skipped --update-goldens test/screenshots
# -> test/screenshots/out/*.png
```

## Notes

- UI language (English/Telugu) and verse script (Devanagari, Telugu script,
  IAST) are independent settings.
- Every text block carries a source line (source, AI-assisted flag, review
  status). Keep it that way for new content.
- Telugu UI strings were drafted with AI assistance and should be reviewed
  by a fluent Telugu reader.
- Fonts: Noto Serif Devanagari, Noto Sans Telugu, Noto Serif (SIL OFL 1.1).
