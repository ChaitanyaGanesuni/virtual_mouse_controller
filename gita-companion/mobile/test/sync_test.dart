import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/core/api/api_client.dart';
import 'package:gita_companion/core/api/token_store.dart';
import 'package:gita_companion/core/db/user_database.dart';
import 'package:gita_companion/core/study/srs.dart';
import 'package:gita_companion/core/study/study_repository.dart';
import 'package:gita_companion/core/study/sync_service.dart';

import 'support/fake_sync_server.dart';

var now = DateTime.utc(2026, 10, 6, 9);

/// One installation of the app: its own database and credentials.
class Device {
  Device(FakeSyncServer server) : db = UserDatabase.memory(), tokens = MemoryTokenStore() {
    api = ApiClient(client: server.client, serverAddress: () => 'https://gita.test', tokens: tokens);
    study = StudyRepository(db, clock: () => now);
    sync = SyncService(db, api, clock: () => now);
  }

  final UserDatabase db;
  final MemoryTokenStore tokens;
  late final ApiClient api;
  late final StudyRepository study;
  late final SyncService sync;

  Future<void> close() => db.close();
}

void tick([Duration d = const Duration(minutes: 1)]) => now = now.add(d);

void main() {
  late FakeSyncServer server;
  final devices = <Device>[];
  Device device() => Device(server)..also(devices.add);

  setUp(() {
    server = FakeSyncServer();
    now = DateTime.utc(2026, 10, 6, 9);
  });
  tearDown(() async {
    for (final d in devices) {
      await d.close();
    }
    devices.clear();
  });

  test('Phase 8 exit criterion: everything survives a reinstall with the recovery code', () async {
    final phone = device();
    await phone.sync.setEnabled(true);
    await phone.sync.setIncludeJournal(true);
    final s = phone.study;
    await s.setBookmarked('2.47', true);
    await s.setFavorite('2.47', true);
    await s.setUnderstood('3.19', true);
    await s.saveNote(verseId: '2.47', kind: NoteKind.question, body: 'What counts as a fruit?');
    await s.saveNote(body: 'A general reflection');
    await s.addHighlight(verseId: '2.47', textId: 'text-1', start: 4, end: 20, color: 'green');
    await s.setNeedsRevision('2.47', true);
    await s.markRead('2.47');
    await s.markRead('2.48');
    await s.completeStep(s.today(), '2.47', PracticeStep.listen);
    await s.saveJournal(s.today(), '2.47', 'Less worry today.');
    tick(const Duration(days: 1));
    await s.review((await s.dueCards()).single, Rating.good);
    await phone.sync.syncNow();
    expect((await phone.sync.status()).pending, 0);
    expect((await phone.sync.status()).lastError, isNull);
    final code = await phone.sync.createRecoveryCode();

    // The phone is reset; the app is installed again.
    await phone.close();
    final again = device();
    await again.sync.restore(code);

    final r = again.study;
    final v = await r.verse('2.47');
    expect((v.bookmarked, v.favorite, v.understood), (true, true, false));
    expect(v.notes.single.body, 'What counts as a fruit?');
    expect(v.notes.single.kind, 'question');
    expect(v.highlights.single.color, 'green');
    expect((await r.verse('3.19')).understood, isTrue);
    expect((await r.watchNotes().first).length, 2);
    final p = await r.progress();
    expect(p.readPerChapter, {2: 2});
    expect((p.cards, p.understood, p.favorites), (2, 1, 1));
    final cards = await again.db.select(again.db.revisionItemsTable).get();
    expect(cards.firstWhere((c) => c.cardType == 'meaning').step, 1);
    expect(await again.db.select(again.db.revisionReviewsTable).get(), hasLength(1));
    final day = (await r.practice('2026-10-06'))!;
    expect(day.journal, 'Less worry today.');
    expect(day.listenedAt, isNotNull);
    expect(await r.watchContinue().first, '2.48');
    final status = await again.sync.status();
    expect((status.enabled, status.pending), (true, 0));
  });

  test('sync is off until turned on', () async {
    final d = device();
    await d.study.setBookmarked('2.47', true);
    await d.sync.syncNow();
    expect(server.requests, isEmpty);
    expect((await d.sync.status()).pending, 1);
  });

  test('the journal stays on the device unless included; turning it off erases it from the server', () async {
    final d = device();
    await d.sync.setEnabled(true);
    await d.study.saveJournal('2026-10-06', '2.47', 'private thoughts');
    await d.sync.syncNow();
    final user = server.lastUser;
    expect(server.stored(user, 'daily_practice')['2026-10-06']!['journal'], isNull);
    expect(server.requests.last.body, isNot(contains('private thoughts')));

    await d.sync.setIncludeJournal(true);
    await d.sync.syncNow();
    expect(server.stored(user, 'daily_practice')['2026-10-06']!['journal'], 'private thoughts');

    await d.sync.setIncludeJournal(false);
    await d.sync.syncNow();
    expect(server.stored(user, 'daily_practice')['2026-10-06']!['journal'], isNull);
    expect((await d.study.practice('2026-10-06'))!.journal, 'private thoughts', reason: 'kept on the device');
  });

  test('two devices: the later edit wins on both, deletions travel', () async {
    final a = device();
    await a.sync.setEnabled(true);
    final noteId = await a.study.saveNote(verseId: '2.47', body: 'first');
    await a.study.setBookmarked('2.47', true);
    await a.sync.syncNow();
    final b = device();
    await b.sync.restore(await a.sync.createRecoveryCode());
    expect((await b.study.verse('2.47')).notes.single.body, 'first');

    // Both edit offline; B's edit is later.
    tick();
    await a.study.saveNote(id: noteId, body: 'edited on A');
    tick();
    await b.study.saveNote(id: noteId, body: 'edited on B');
    await b.study.setBookmarked('2.47', false);
    await b.sync.syncNow();
    await a.sync.syncNow(); // A's older edit loses and A receives B's.
    await b.sync.syncNow();
    for (final d in [a, b]) {
      final v = await d.study.verse('2.47');
      expect(v.notes.single.body, 'edited on B');
      expect(v.bookmarked, isFalse);
      expect((await d.sync.status()).pending, 0);
    }
  });

  test('reading history merges across devices', () async {
    final a = device();
    await a.sync.setEnabled(true);
    await a.study.markRead('2.47');
    await a.sync.syncNow();
    final b = device();
    await b.sync.restore(await a.sync.createRecoveryCode());
    tick();
    await b.study.markRead('2.47');
    await b.study.markRead('2.47');
    await b.sync.syncNow();
    await a.sync.syncNow();
    final read = await (a.db.select(
      a.db.versesReadTable,
    )..where((t) => t.verseId.equals('2.47'))).getSingle();
    expect(read.readCount, 3);
  });

  test('many changes arrive over several pages', () async {
    server = FakeSyncServer(page: 7);
    final a = device();
    await a.sync.setEnabled(true);
    for (var v = 1; v <= 40; v++) {
      await a.study.setBookmarked('2.$v', true);
    }
    await a.sync.syncNow();
    final b = device();
    await b.sync.restore(await a.sync.createRecoveryCode());
    expect(await b.study.watchBookmarks().first, hasLength(40));
  });

  test('a failed sync keeps the changes and reports the error', () async {
    final d = device();
    await d.sync.setEnabled(true);
    await d.study.setBookmarked('2.47', true);
    server.failNextSync = 503;
    await d.sync.syncNow();
    var status = await d.sync.status();
    expect((status.lastError, status.pending), ('server_error', 1));
    await d.sync.syncNow();
    status = await d.sync.status();
    expect((status.lastError, status.pending), (null, 0));
    expect(status.lastSyncAt, isNotNull);
  });

  test('a new account (old credentials lost) receives everything again', () async {
    final d = device();
    await d.sync.setEnabled(true);
    await d.study.setBookmarked('2.47', true);
    await d.sync.syncNow();
    final first = server.lastUser;
    await d.tokens.clear(); // e.g. the Keystore was reset
    await d.sync.syncNow();
    expect(server.lastUser, isNot(first));
    expect(server.stored(server.lastUser, 'bookmark').keys, ['2.47']);
  });

  test('no server set up: sync stays quiet', () async {
    final db = UserDatabase.memory();
    addTearDown(db.close);
    final sync = SyncService(
      db,
      ApiClient(client: server.client, serverAddress: () => '', tokens: MemoryTokenStore()),
    );
    await sync.setEnabled(true);
    await sync.syncNow();
    expect(server.requests, isEmpty);
  });
}

extension<T> on T {
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}
