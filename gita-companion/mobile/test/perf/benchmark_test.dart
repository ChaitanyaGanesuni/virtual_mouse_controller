import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/core/audio/manifest_resolver.dart';
import 'package:gita_companion/core/content/content_pack.dart';
import 'package:gita_companion/core/content/sqlite_content_repository.dart';
import 'package:gita_companion/core/db/user_database.dart';
import 'package:gita_companion/core/search/search_service.dart';
import 'package:gita_companion/core/study/srs.dart';
import 'package:gita_companion/core/study/study_repository.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:yaml/yaml.dart';

import '../support/pack.dart';

/// Timings of what a user waits for, on the CI machine. A mid-range phone
/// is roughly 3-5x slower, so each budget is the phone target divided by 4;
/// a budget failing means a real regression, not noise. Results are printed
/// for docs/PHASE-10.md.
final results = <String, String>{};

Future<Duration> time(Future<void> Function() f) async {
  final sw = Stopwatch()..start();
  await f();
  return sw.elapsed;
}

Duration timeSync(void Function() f) {
  final sw = Stopwatch()..start();
  f();
  return sw.elapsed;
}

String ms(Duration d) => '${(d.inMicroseconds / 1000).toStringAsFixed(1)} ms';

double percentile(List<Duration> xs, double p) {
  final s = [...xs]..sort();
  return s[((s.length - 1) * p).round()].inMicroseconds / 1000;
}

void main() {
  tearDownAll(() {
    for (final e in results.entries) {
      // ignore: avoid_print
      print('BENCH ${e.key}: ${e.value}');
    }
  });

  test('cold start: content pack install and opening', () async {
    final dir = Directory.systemTemp.createTempSync('bench');
    late Database db;
    final first = await time(() async {
      db = await ContentPackInstaller(directory: dir, loadAsset: loadAssetFromDisk).install();
    });
    db.close();
    final again = await time(() async {
      db = await ContentPackInstaller(directory: dir, loadAsset: loadAssetFromDisk).install();
    });
    late SqliteContentRepository repo;
    final open = timeSync(() => repo = SqliteContentRepository(db));
    results['first install (copy 4 MB pack)'] = ms(first);
    results['later starts: verify installed pack'] = ms(again);
    results['open content repository'] = ms(open);
    expect(first, lessThan(const Duration(milliseconds: 1500)));
    expect(again, lessThan(const Duration(milliseconds: 250)));
    expect(open, lessThan(const Duration(milliseconds: 100)));
    expect(repo.chapters(), hasLength(18));
    db.close();
  });

  test('reading: a verse, a chapter', () {
    final repo = openRealRepository();
    final ids = repo.readingOrder();
    final verse = <Duration>[for (final id in ids) timeSync(() => repo.verse(id))];
    final chapter = <Duration>[for (var c = 1; c <= 18; c++) timeSync(() => repo.versesOf(c))];
    results['open a verse (p50 / p95)'] = '${percentile(verse, .5)} / ${percentile(verse, .95)} ms';
    results['open a chapter (p50 / max)'] = '${percentile(chapter, .5)} / ${percentile(chapter, 1)} ms';
    expect(percentile(verse, .95), lessThan(4));
    expect(percentile(chapter, 1), lessThan(40));
  });

  test('search: first query, then the golden-set questions', () {
    final db = sqlite3.open(requirePack().path, mode: OpenMode.readOnly);
    addTearDown(db.close);
    final ids = {for (final r in db.select('SELECT id FROM verse')) r['id'] as String};
    final search = SqliteSearchService(db, verseExists: ids.contains);
    final first = timeSync(() => search.search('anger'));
    final golden =
        (loadYaml(File('../content/eval/golden.yaml').readAsStringSync()) as YamlMap)['questions']
            as YamlList;
    final times = <Duration>[
      for (final g in golden.cast<YamlMap>()) timeSync(() => search.search(g['q'] as String)),
    ];
    final typing = <Duration>[
      for (final q in ['k', 'ka', 'kar', 'karm', 'karma', 'karman', 'karmany', 'karmanye'])
        timeSync(() => search.search(q)),
    ];
    results['first search (loads the concept index)'] = ms(first);
    results['question search (p50 / p95, ${times.length} questions)'] =
        '${percentile(times, .5)} / ${percentile(times, .95)} ms';
    results['search while typing (p95)'] = '${percentile(typing, .95)} ms';
    expect(first, lessThan(const Duration(milliseconds: 300)));
    expect(percentile(times, .95), lessThan(40));
    expect(percentile(typing, .95), lessThan(25));
  });

  test('listening: building chapter playlists', () {
    final resolver = ManifestResolver(openRealRepository());
    final t = <Duration>[for (var c = 1; c <= 18; c++) timeSync(() => resolver.chapter(c, 'en'))];
    results['chapter playlist (max of 18)'] = '${percentile(t, 1)} ms';
    expect(percentile(t, 1), lessThan(30));
  });

  test('My Gita with a lot of data stays quick', () async {
    final db = UserDatabase.memory();
    addTearDown(db.close);
    var now = DateTime.utc(2026, 1, 1);
    final study = StudyRepository(db, clock: () => now);
    final ids = openRealRepository().readingOrder();
    await db.transaction(() async {
      for (final id in ids) {
        await study.markRead(id);
      }
      for (final id in ids.take(300)) {
        await study.setNeedsRevision(id, true);
        await study.saveNote(verseId: id, body: 'A note on $id ' * 20);
      }
    });
    now = now.add(const Duration(days: 3));
    final progress = await time(() => study.progress());
    final due = await time(() => study.dueCards());
    final cards = await study.dueCards();
    final review = await time(() => study.review(cards.first, Rating.good));
    final verse = await time(() => study.verse('2.47'));
    results['My Gita progress (701 read, 600 cards)'] = ms(progress);
    results['cards due today (${cards.length})'] = ms(due);
    results['grade one card'] = ms(review);
    results['study data of a verse'] = ms(verse);
    expect(progress, lessThan(const Duration(milliseconds: 60)));
    expect(due, lessThan(const Duration(milliseconds: 40)));
    expect(review, lessThan(const Duration(milliseconds: 25)));
    expect(verse, lessThan(const Duration(milliseconds: 15)));
  });
}
