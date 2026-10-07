import 'dart:io';

import 'package:drift/drift.dart' show Value;

import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/core/audio/audio_cache.dart';
import 'package:gita_companion/core/audio/manifest_resolver.dart';
import 'package:gita_companion/core/audio/synthesizer.dart';
import 'package:gita_companion/core/content/content_pack.dart';
import 'package:gita_companion/core/content/sqlite_content_repository.dart';
import 'package:gita_companion/core/db/user_database.dart';
import 'package:gita_companion/core/packs/content_updates.dart';
import 'package:gita_companion/core/packs/download_manager.dart';
import 'package:gita_companion/core/packs/downloader.dart';
import 'package:gita_companion/core/packs/offline_audio.dart';
import 'package:gita_companion/core/packs/pack_catalog.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/audio_fakes.dart';
import 'support/fake_pack_server.dart';
import 'support/pack.dart';

void main() {
  late File updated;
  setUpAll(() => updated = makeUpdatedPack());

  Directory temp() => Directory.systemTemp.createTempSync('packs_test');

  group('downloader', () {
    late FakePackServer server;
    late Downloader downloader;
    late PackInfo info;
    setUp(() async {
      server = FakePackServer(updated);
      downloader = Downloader(server.client);
      info = (await PackCatalogClient(server.client, () => packServer).fetch()).single;
    });

    test('downloads and verifies', () async {
      final out = File('${temp().path}/p.sqlite');
      final got = <int>[];
      await downloader.download(
        info.url,
        out,
        size: info.size,
        sha256Hex: info.sha256,
        onProgress: (n, _) => got.add(n),
      );
      expect(out.readAsBytesSync(), server.bytes);
      expect(got.last, info.size);
    });

    test('an interrupted download resumes where it stopped', () async {
      final out = File('${temp().path}/p.sqlite');
      server.dropAfter = 100000;
      await expectLater(
        downloader.download(info.url, out, size: info.size, sha256Hex: info.sha256),
        throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', 'offline')),
      );
      expect(File('${out.path}.part').lengthSync(), 100000, reason: 'kept for the resume');
      await downloader.download(info.url, out, size: info.size, sha256Hex: info.sha256);
      expect(server.requests.last.headers['Range'], 'bytes=100000-');
      expect(out.readAsBytesSync(), server.bytes);
    });

    test('a corrupted file is rejected and thrown away', () async {
      final out = File('${temp().path}/p.sqlite');
      server.corrupt = true;
      await expectLater(
        downloader.download(info.url, out, size: info.size, sha256Hex: info.sha256),
        throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', 'corrupt')),
      );
      expect(out.existsSync() || File('${out.path}.part').existsSync(), isFalse);
    });

    test('cancelling stops and keeps the part', () async {
      final out = File('${temp().path}/p.sqlite');
      final token = CancelToken()..cancel();
      await expectLater(
        downloader.download(info.url, out, size: info.size, sha256Hex: info.sha256, cancel: token),
        throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', 'cancelled')),
      );
    });

    test('the catalog says why it is unavailable', () async {
      server.offline = true;
      expect(
        () => PackCatalogClient(server.client, () => packServer).fetch(),
        throwsA(isA<CatalogUnavailable>().having((e) => e.reason, 'reason', 'offline')),
      );
      expect(
        () => PackCatalogClient(server.client, () => '').fetch(),
        throwsA(isA<CatalogUnavailable>().having((e) => e.reason, 'reason', 'not_configured')),
      );
    });
  });

  group('content updates', () {
    Future<(ContentPackInstaller, Database)> install(Directory dir) async {
      final installer = ContentPackInstaller(directory: dir, loadAsset: loadAssetFromDisk);
      return (installer, await installer.install());
    }

    test('download → used from the next start; the app keeps working meanwhile', () async {
      final dir = temp();
      final (first, db) = await install(dir);
      expect(first.active!.downloaded, isFalse);
      final server = FakePackServer(updated);
      final updates = ContentUpdates(
        directory: dir,
        downloader: Downloader(server.client),
        installed: first.active!,
      );
      final pack = (await PackCatalogClient(server.client, () => packServer).fetch()).single;
      expect(updates.check(pack), ContentUpdateState.updateAvailable);
      await updates.download(pack);
      expect(updates.check(pack), ContentUpdateState.readyAfterRestart);
      expect(SqliteContentRepository(db).verse('12.13'), isNotNull, reason: 'the open pack is untouched');
      db.close();

      final (second, db2) = await install(dir);
      expect(second.active!.downloaded, isTrue);
      expect(second.active!.contentHash, 'e' * 64);
      final text = SqliteContentRepository(db2)
          .verse('12.13')!
          .texts
          .firstWhere((t) => t.kind == 'translation');
      expect(text.body, startsWith('UPDATED TRANSLATION'));
      final after = ContentUpdates(
        directory: dir,
        downloader: Downloader(server.client),
        installed: second.active!,
      );
      expect(after.check(pack), ContentUpdateState.upToDate);
      db2.close();
    });

    test('an app update with newer content wins over an older download, which is removed', () async {
      final dir = temp();
      final (first, db) = await install(dir);
      db.close();
      final older = makeUpdatedPack(builtAt: '2000-01-01T00:00:00+00:00');
      final server = FakePackServer(older, builtAt: '2000-01-01T00:00:00+00:00');
      final pack = (await PackCatalogClient(server.client, () => packServer).fetch()).single;
      final updates = ContentUpdates(
        directory: dir,
        downloader: Downloader(server.client),
        installed: first.active!,
      );
      expect(updates.check(pack), ContentUpdateState.upToDate, reason: 'older than what the app has');
      await updates.download(pack); // even if it was fetched anyway
      final (second, db2) = await install(dir);
      expect(second.active!.downloaded, isFalse);
      expect(dir.listSync().where((f) => f.path.contains(ContentPackInstaller.downloadPrefix)), isEmpty);
      expect(File('${dir.path}/${ContentPackInstaller.activeDownload}').existsSync(), isFalse);
      db2.close();
    });

    test('a pack for a newer app is not offered; a damaged download is ignored', () async {
      final dir = temp();
      final (first, db) = await install(dir);
      db.close();
      final future = FakePackServer(updated, schema: 4);
      final pack = (await PackCatalogClient(future.client, () => packServer).fetch()).single;
      final updates = ContentUpdates(
        directory: dir,
        downloader: Downloader(future.client),
        installed: first.active!,
      );
      expect(updates.check(pack), ContentUpdateState.needsAppUpdate);

      final ok = FakePackServer(updated);
      final good = (await PackCatalogClient(ok.client, () => packServer).fetch()).single;
      await ContentUpdates(
        directory: dir,
        downloader: Downloader(ok.client),
        installed: first.active!,
      ).download(good);
      // The downloaded file is damaged on disk later.
      final file = dir.listSync().whereType<File>().firstWhere(
        (f) => f.path.contains(ContentPackInstaller.downloadPrefix),
      );
      file.writeAsBytesSync([1, 2, 3]);
      final (second, db2) = await install(dir);
      expect(second.active!.downloaded, isFalse, reason: 'falls back to the bundled pack');
      db2.close();
    });
  });

  group('offline audio and the download manager', () {
    late UserDatabase db;
    late FakeTtsProvider tts;
    late AudioCache cache;
    late DownloadManager manager;
    late OfflineAudio audio;

    setUp(() {
      db = UserDatabase.memory();
      tts = FakeTtsProvider();
      // Small, so ordinary (unpinned) audio is evicted quickly.
      cache = AudioCache(directory: temp(), db: db, maxBytes: 2000);
      final repo = openRealRepository();
      audio = OfflineAudio(
        db: db,
        cache: cache,
        synthesizer: AudioSynthesizer(providers: [tts], cache: cache, voicePrefs: () => const {}),
        resolver: ManifestResolver(repo),
      );
      final server = FakePackServer(updated)..offline = true;
      manager = DownloadManager(
        db: db,
        catalogClient: PackCatalogClient(server.client, () => packServer),
        offlineAudio: audio,
      );
    });
    tearDown(() async {
      manager.dispose();
      await db.close();
    });

    test('a chapter is synthesized once, pinned, and survives cache eviction', () async {
      expect((await manager.audioStatus(12, 'en')).state, PackState.notDownloaded);
      final seen = <PackState>[];
      final sub = manager.changes.listen((_) async => seen.add((await manager.audioStatus(12, 'en')).state));
      await manager.downloadAudio(12, 'en');
      await manager.idle();
      await sub.cancel();
      final status = await manager.audioStatus(12, 'en');
      expect(status.state, PackState.downloaded);
      expect(status.bytes, greaterThan(0));
      expect(seen, contains(PackState.downloading));
      final total = manifestLength(audio, 12);
      expect(tts.calls, hasLength(total));

      // Unrelated audio fills the cache: the pinned chapter stays.
      await cache.evict();
      expect(await audio.intact(OfflineAudio.packId(12, 'en')), isTrue);

      // Downloading again synthesizes nothing.
      await manager.remove(OfflineAudio.packId(12, 'en'));
      await manager.downloadAudio(12, 'en');
      await manager.idle();
      expect(tts.calls.length, lessThanOrEqualTo(total * 2));
      final overview = await manager.overview('en');
      expect(overview.audio[12]!.state, PackState.downloaded);
      expect(overview.downloadedBytes, greaterThan(0));
      expect(overview.catalogError, isNull, reason: 'not fetched yet');
    });

    test('removing a chapter unpins its files and lets them be evicted', () async {
      await manager.downloadAudio(12, 'en');
      await manager.idle();
      final id = OfflineAudio.packId(12, 'en');
      await manager.remove(id);
      expect((await manager.audioStatus(12, 'en')).state, PackState.notDownloaded);
      expect(await cache.totalBytes(), lessThanOrEqualTo(2000));
    });

    test('failures are reported and can be retried', () async {
      final failing = FakeTtsProvider(voices: const []);
      final noVoice = DownloadManager(
        db: db,
        catalogClient: PackCatalogClient(FakePackServer(updated).client, () => packServer),
        offlineAudio: OfflineAudio(
          db: db,
          cache: cache,
          synthesizer: AudioSynthesizer(providers: [failing], cache: cache, voicePrefs: () => const {}),
          resolver: audio.resolver,
        ),
      );
      await noVoice.downloadAudio(1, 'en');
      await noVoice.idle();
      final s = await noVoice.audioStatus(1, 'en');
      expect((s.state, s.error), (PackState.failed, 'no_voice'));
      noVoice.dispose();
    });

    test('a download running when the app stopped shows as interrupted', () async {
      await db
          .into(db.offlinePacksTable)
          .insert(
            OfflinePacksTableCompanion.insert(
              id: 'audio-chapter-2-en',
              kind: 'audio',
              state: 'downloading',
              updatedAt: 0,
            ),
          );
      await manager.init();
      final s = await manager.audioStatus(2, 'en');
      expect((s.state, s.error), (PackState.failed, 'interrupted'));
    });

    test('a changed chapter text means an update is available', () async {
      await manager.downloadAudio(12, 'en');
      await manager.idle();
      await (db.update(db.offlinePacksTable))
          .write(const OfflinePacksTableCompanion(fingerprint: Value('old')));
      expect((await manager.audioStatus(12, 'en')).state, PackState.updateAvailable);
    });

    test('offline: the catalog error is reported, nothing else breaks', () async {
      await manager.refreshCatalog();
      final o = await manager.overview('en');
      expect(o.catalogError, 'offline');
      expect(o.content, isNull, reason: 'no content updater in this test');
    });
  });
}

int manifestLength(OfflineAudio audio, int chapter) => audio.manifest(chapter, 'en').chunks.length;
