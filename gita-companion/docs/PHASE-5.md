# Phase 5 report: Audio system

## What was built

### Architecture (mobile, `lib/core/audio/`)

```
text ─► normalise (verse refs spoken, dandas → pauses) ─► sentences ─► chunks (≤300 chars)
     ─► manifest (ordered chunks: verse, section, language, rate)
     ─► synthesizer: choose provider + voice ─► cache hit? ─► else synthesize to file
     ─► content-addressed cache (sha256 of text|language|provider|version|voice|rate)
     ─► player: chunk after chunk, prefetching the next 2, one global timeline
```

- **`TtsProvider` interface**: `getVoices`, `getSupportedLanguages`,
  `capabilities`, `synthesizeToFile`. Every engine produces a file, so the
  cache and player are the same for all of them. Device TTS is implemented;
  other engines plug in through the provider list without touching any
  other code.
- **Voice choice:** the user's preferred voice first, then offline and
  Indian-locale voices. Sanskrit falls back to a Hindi voice, which is
  flagged *approximate* and shown in the player.
- **Cache:** identical audio is never synthesized twice. Playback speed is
  *not* part of the key (the player changes speed), so the cache doesn't
  grow sixfold. Provider version and synthesis rate *are* part of it. The
  cache is limited to 300 MB with LRU eviction, and pinned (downloaded)
  files are never evicted.
- **Playback controller:**
  - play/pause, seek on one timeline across chunks, ±15 s, next/previous
    verse (previous restarts the verse if you are more than 3 s in);
  - speeds 0.75–2×, Repeat ×3;
  - real durations read from WAV headers as chunks are prefetched;
  - a failing chunk is retried once, then skipped so playback never stalls;
  - a missing voice pauses with guidance on how to install one.
- **Resume:** chapter, verse, chunk, position and speed are saved every 5 s
  and on pause, and playback continues exactly there after the app is
  closed. Home shows **Continue listening** with "Listening progress: N%".
- **Background playback:** `audio_service` provides the media notification,
  lock screen and Bluetooth controls (next/previous = verse, fast-forward/
  rewind = 15 s). Android permissions for foreground media playback were
  added. The app still has **no internet permission**.

### Screens
- **Verse screen:** Recite; Recite slowly; Repeat 3 times (normal or slow);
  Listen (recitation followed by the explanation shown); and a speaker
  button on each explanation ("Read this explanation aloud").
- **Chapter screen:** Start listening plays the whole chapter: every verse
  recited, each followed by its simple explanation where one exists.
- **Full player:** verse, chapter, section and repetition; the passage being
  read (shown as written, not as prepared for the engine); the approximate
  pronunciation notice; elapsed and remaining time; transport controls and
  speed chips.
- **Mini player:** stays at the bottom of every screen while audio plays.
- **Settings → Voices:** a voice per language (English, Telugu, Sanskrit),
  with a preview. Previews are never saved as listening progress.

### Sanskrit recitation, high-quality path (`backend/`)
- A Python `TTSProvider` interface and an **Indic Parler-TTS** adapter
  (Apache-2.0, native Sanskrit and Telugu speakers).
- `workers/generate_recitation.py` pre-generates normal and slow recitation
  per verse, resumably. It writes a manifest (hash, duration, model, voice,
  licence) and a `review.csv` pronunciation sheet, with every file
  `unreviewed`. It needs a GPU; a free Kaggle or Colab GPU is enough.
  Shipping the packs to phones is part of Phase 9 (offline downloads).

## Tests

| Package | Tests | New in Phase 5 |
|---|---|---|
| mobile | 90 | text prep, hashing, manifests, cache/LRU, synthesizer, WAV parsing, 12 playback-controller tests, 7 audio-UI tests, v1→v2 migration, voice settings |
| backend | 69 | recitation batch (fake engine), Indic Parler metadata, WAV helpers |
| content | 87 | unchanged |

## Problems found and fixed

1. **The mini player crashed:** it sits above the navigator, where there is
   no overlay for tooltips. This would also have crashed on a phone. It now
   uses semantic labels instead.
2. **The mini player rebuilt during navigation:** it listened to the router
   and swapped its widget tree, causing a framework `!_dirty` assertion. Its
   tree is now stable, and the player screen signals itself after the frame.
3. **Tapping Recite waited for synthesis** before opening the player, so it
   would have felt frozen. The player now opens immediately and shows a
   loading state.
4. **Choosing a voice silently did nothing:** `copyWith` dropped the
   setting. Found by a widget test; regression test added.
5. Verse references at the end of a sentence ("Compare 3.19.") were not
   converted to speech.
6. The sentence splitter would have split decimals ("1.5").
7. Merging a tiny last chunk could exceed the chunk limit.
8. The player showed the engine's version of the text ("कदाचन ,"). It now
   shows the verse as written.
9. "Sanskrit terms" are stored as JSON and would have been read out as
   brackets and quotes. They are now spoken as "term: meaning." sentences.

## Limitations

- No phone can test audio in this environment. Synthesis, the player and
  background service are tested through fakes and interfaces, and the APK
  is built by CI. **Please try it on a device**, especially:
  - whether a Telugu voice is installed (Settings → Accessibility →
    Text-to-speech);
  - how the Hindi voice handles Sanskrit;
  - the lock-screen controls.
- Device TTS quality varies by phone and engine.
- Pre-generated Indic Parler recitation exists as a pipeline only. It needs
  a GPU run, a pronunciation review, and the Phase 9 download mechanism
  before it reaches phones.
- "Download for offline listening" is Phase 9. Audio is already cached
  after first play, and works offline when device voices are installed.
