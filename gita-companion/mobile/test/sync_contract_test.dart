import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/core/api/api_client.dart';
import 'package:gita_companion/core/api/token_store.dart';
import 'package:gita_companion/core/db/user_database.dart';
import 'package:gita_companion/core/study/srs.dart';
import 'package:gita_companion/core/study/study_repository.dart';
import 'package:gita_companion/core/study/sync_service.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/fake_sync_server.dart';
import 'support/pack.dart';

/// The app and the server must agree on the sync format. This test records
/// the exact request the app sends for one item of every kind, and compares
/// it with backend/tests/fixtures/sync_request_from_app.json; the backend
/// tests send that file to the real server and require every item to be
/// accepted. Regenerate after a deliberate format change with
///   UPDATE_CONTRACT=1 flutter test test/sync_contract_test.dart
const fixture = '../backend/tests/fixtures/sync_request_from_app.json';

final _uuid = RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}');

void main() {
  test('the app sends what the server accepts (shared fixture)', () async {
    final pack = sqlite3.open(requirePack().path, mode: OpenMode.readOnly);
    addTearDown(pack.close);
    // A real text id: the server checks it belongs to the verse.
    final textId =
        pack
                .select("SELECT id FROM verse_text WHERE verse_id = '2.47' AND kind = 'translation' LIMIT 1")
                .first['id']
            as String;

    var now = DateTime.utc(2026, 1, 6, 9);
    final server = FakeSyncServer();
    final db = UserDatabase.memory();
    addTearDown(db.close);
    final api = ApiClient(
      client: server.client,
      serverAddress: () => 'https://gita.test',
      tokens: MemoryTokenStore(),
    );
    final study = StudyRepository(db, clock: () => now);
    final sync = SyncService(db, api, clock: () => now);
    await sync.setEnabled(true);
    await sync.setIncludeJournal(true);

    await study.setBookmarked('2.47', true);
    await study.setFavorite('2.47', true);
    await study.addHighlight(verseId: '2.47', textId: textId, start: 4, end: 20);
    await study.saveNote(verseId: '2.47', kind: NoteKind.question, body: 'What counts as a fruit?');
    await study.setNeedsRevision('2.47', true);
    now = now.add(const Duration(days: 1));
    await study.review((await study.dueCards()).single, Rating.good);
    await study.completeStep('2026-01-07', '2.47', PracticeStep.listen);
    await study.saveJournal('2026-01-07', '2.47', 'Calm today.');
    await study.markRead('2.47');
    await sync.syncNow();

    final sent = server.requests.firstWhere((r) => r.url.path == '/v1/sync');
    final body = const JsonEncoder.withIndent('  ').convert(jsonDecode(sent.body));
    expect((jsonDecode(sent.body)['changes'] as Map).keys.toSet(), {
      'bookmark',
      'verse_state',
      'highlight',
      'note',
      'revision_item',
      'revision_review',
      'daily_practice',
      'verse_read',
      'reading_progress',
    }, reason: 'one item of every kind');
    if (Platform.environment['UPDATE_CONTRACT'] == '1') {
      File(fixture).writeAsStringSync('$body\n');
    }
    // Random ids differ from run to run; everything else must match.
    String normalize(String s) => s.replaceAll(_uuid, '<uuid>');
    expect(normalize(body), normalize(File(fixture).readAsStringSync().trim()));
  });
}
