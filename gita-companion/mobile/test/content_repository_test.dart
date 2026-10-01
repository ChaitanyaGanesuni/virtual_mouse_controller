import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/core/content/models.dart';
import 'package:gita_companion/core/content/sqlite_content_repository.dart';

import 'support/pack.dart';

void main() {
  late SqliteContentRepository repo;
  setUpAll(() => repo = openRealRepository());

  test('18 chapters with standard verse counts', () {
    final counts = repo.chapters().map((c) => c.verseCount).toList();
    expect(counts, [47, 72, 43, 42, 29, 47, 30, 28, 34, 42, 55, 20, 34, 27, 20, 24, 28, 78]);
    expect(counts.reduce((a, b) => a + b), 700);
    expect(repo.chapter(2).nameSa, 'साङ्ख्ययोग');
    expect(repo.chapter(2).nameIn(VerseScript.iast), 'sāṅkhyayoga');
    expect(repo.chapter(2).nameIn(VerseScript.telugu), 'సాఙ్ఖ్యయోగ');
    expect(() => repo.chapter(19), throwsArgumentError);
  });

  test('verse 2.47 in three scripts', () {
    final v = repo.verse('2.47')!;
    expect(v.sanskrit, startsWith('कर्मण्येवाधिकारस्ते मा फलेषु कदाचन ।'));
    expect(v.textIn(VerseScript.iast), startsWith('karmaṇyevādhikāraste'));
    expect(v.textIn(VerseScript.telugu), startsWith('కర్మణ్యేవాధికారస్తే'));
    expect(v.isCanonical, isTrue);
    expect(repo.verse('2.73'), isNull);
  });

  test('speakers and the non-canonical 13.0', () {
    expect(repo.verse('1.1')!.speaker!.id, 'dhritarashtra');
    expect(repo.verse('2.11')!.speaker!.lines['sa-Latn'], 'śrībhagavānuvāca');
    final ch13 = repo.versesOf(13);
    expect(ch13.first.id, '13.0');
    expect(ch13.first.isCanonical, isFalse);
    expect(ch13.length, 35);
  });

  test('reading order crosses chapter boundaries', () {
    expect(repo.previousVerseId('1.1'), isNull);
    expect(repo.nextVerseId('1.47'), '2.1');
    expect(repo.previousVerseId('2.1'), '1.47');
    expect(repo.nextVerseId('12.20'), '13.0');
    expect(repo.nextVerseId('18.78'), isNull);
  });

  test('verse of the day is deterministic and canonical', () {
    final a = repo.verseOfTheDay(DateTime(2026, 10, 1, 7));
    final b = repo.verseOfTheDay(DateTime(2026, 10, 1, 23, 59));
    expect(a.id, b.id);
    final days = [
      for (var d = 0; d < 60; d++) repo.verseOfTheDay(DateTime(2026, 1, 1).add(Duration(days: d))).id,
    ];
    expect(days.every((id) => repo.verse(id)!.isCanonical), isTrue);
    expect(days.toSet().length, greaterThan(50), reason: 'consecutive days should rarely repeat');
  });

  test('dayIndex is stable across platforms (fixed vectors)', () {
    expect(dayIndex(DateTime(2026, 10, 1), 700), dayIndex(DateTime.utc(2026, 10, 1), 700));
    for (var d = 0; d < 1000; d++) {
      final i = dayIndex(DateTime(2020).add(Duration(days: d)), 700);
      expect(i, inInclusiveRange(0, 699));
    }
  });

  test('sources carry licences and AI flags', () {
    final editorial = repo.source('gita-companion-editorial')!;
    expect(editorial.isAiGenerated, isTrue);
    expect(repo.source('bg-sanskrit-gita-json')!.isAiGenerated, isFalse);
    expect(repo.sources().every((s) => s.license.isNotEmpty), isTrue);
  });
}
