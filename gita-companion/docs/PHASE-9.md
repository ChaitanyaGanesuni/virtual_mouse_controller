# Phase 9 report: Offline downloads

Exit criterion: *airplane-mode test of all downloaded features.* **Met.**

`mobile/test/airplane_mode_test.dart` runs the whole scenario in the real app:

1. **Online.** From *Settings → Downloads & storage*, it downloads the content update and makes chapter 12's audio available offline. It also bookmarks a verse.
2. **Airplane mode.** Every network request now fails and the speech engine stops working. The app is restarted.
3. **What still works:**
   - the **updated content** is in use, and the reader shows the new translation text;
   - **chapter 12 plays** from the downloaded audio, with **nothing synthesized again**;
   - **search by meaning** still answers;
   - **My Gita** still shows the bookmark;
   - the Downloads screen still lists the chapter as available offline, and says plainly that updates can't be checked without a connection;
   - the **AI teacher** says it needs the internet, the one thing it cannot do offline.

## What was built

### Downloadable packs (server)

**Catalog.** `GET /v1/packs` lists each pack with its version, size and SHA-256. The **content pack** is built into the server image from the deployed dataset. When new AI explanations or reviewed corrections are deployed, phones can download them **without a new app release**. Packs hosted elsewhere (for example recitation audio in object storage) can be listed in `packs/extra.json` with HTTPS URLs and checksums.

**Downloads.** `GET /v1/packs/files/{name}` supports **HTTP Range**, so an interrupted download continues where it stopped. Rules:

- Only files in the catalog are served, so a path trick cannot read anything else.
- New downloads are limited per network address. Resumed downloads are not counted again.

I built the Docker image and ran it against Postgres. The catalog is correct, and a download taken in two ranges reassembles to exactly the catalog's checksum.

### Download manager (app)

**States**, as planned in the architecture: not downloaded → queued → downloading (with progress) → downloaded, or failed (with a retry), and update available.

- Downloads run one at a time, and their state is kept in the app's database (schema v5).
- A download that was running when the app was closed shows as *interrupted*. Trying again resumes it.

**Downloads are verified.** A file is accepted only if both match the catalog:

- its size, and its SHA-256;
- for content, also: SQLite integrity, the schema version, the content hash and the build time.

A damaged download is discarded. A download cut off part-way is kept as a `.part` file and resumed later.

**Content updates take effect at the next start.** The open database is never swapped while the app is running. Precedence rules:

- A downloaded pack is used only if it is newer than the one bundled with the app. When the app is updated with newer content, it wins and the older download is deleted.
- A pack that needs a newer app is not offered.
- A broken download falls back to the bundled pack.

**Chapter audio for offline listening.** Each verse is recited, followed by its simple explanation in the user's explanation language.

- **How it is made.** The audio is prepared **on the phone** with its own voices (free, no server), and every file is **pinned** in the audio cache, so it is never evicted.
- **Removing.** Removing a chapter unpins only files that no other download needs.
- **Updates.** If the chapter's texts change (after a content update), the chapter shows *update available*. Already-prepared pieces are reused.

### Screens

- **Settings → Downloads & storage:**
  - how much space downloads use, and how much all audio on the phone uses;
  - the content update, with its size;
  - all 18 chapters, each with its state, an estimated or actual size, and actions: download, cancel, retry, update, remove (with confirmation).
- **Chapter screen:** a *Make available offline* button that shows progress and a check mark when done.

Screenshots are in `mobile/test/screenshots/out/` (`downloads.png`, `downloads_telugu_dark.png`).

## Tests

| Part | Tests | New in Phase 9 |
|---|---|---|
| backend | 136 | Catalog, full and resumed downloads, ETag, only catalogued files served, rate limit (resumes exempt), no packs directory |
| mobile | 205 | Downloader (verify, resume, corrupt, cancel), content updates (next-start use, newer app wins, needs-app-update, damaged file falls back), offline audio (pinned through eviction, remove, no voice, interrupted, update available), and the airplane-mode test |

## Problems found and fixed

- **The audio cache could delete a file it had just written.** When the cache was over its size limit, adding a file triggered an eviction that could remove that same file before it was played or pinned. This affected normal playback too, not only downloads. The newest file is now never evicted by its own insertion.
- **A test helper hung.** Waiting on a download inside the widget test's fake clock never finished. The test now pumps frames until the queue is empty, and the manager exposes a `busy` flag.
- **The Downloads screen no longer shows a spinner while loading.** It loads in milliseconds from the local database, and a spinner that never stops would also keep widget tests from settling.

## Limitations and decisions for you

1. **Audio files are large.** Roughly 10–40 MB per chapter (estimated; the screen shows each estimate before downloading), because Android's speech engine writes uncompressed WAV. Compressing to Opus (about 10× smaller) needs a native encoder; I recommend it for Phase 10.
2. **Offline audio uses the phone's voices.** The Sanskrit is read by a Hindi voice and labelled "approximate", as before. Proper recitation needs the GPU batch from Phase 5. Once that audio is generated and uploaded, it can be listed in `extra.json`; the app then needs a small "recordings" voice provider to play it. I've left that until the recordings exist.
3. **No on-device search model.** Phase 7 met its Telugu target and came within 0.006 of the English one without embeddings, so the app needs no separate model download. That keeps the APK and downloads small.
4. **No "Wi-Fi only" switch.** That needs a connectivity plugin. Content updates are about 4 MB, and chapter audio is made on the phone, not downloaded, so this matters little today. It becomes worth adding once recitation packs are downloaded from the server.
5. **Content updates apply at the next start**, by design: the open database is never replaced underneath the reader.
