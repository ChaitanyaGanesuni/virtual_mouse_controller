import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/core/content/sqlite_content_repository.dart';
import 'package:gita_companion/core/search/search_service.dart';

import 'support/pack.dart';

void main() {
  late SqliteSearchService search;
  setUpAll(() {
    final db = openPackWithSampleAi();
    final ids = SqliteContentRepository(db).readingOrder().toSet();
    search = SqliteSearchService(db, verseExists: ids.contains);
  });

  List<String> ids(String q) => search.search(q).map((h) => h.verseId).toList();

  test('verse references jump straight to the verse', () {
    for (final q in ['2.47', 'BG 2:47', '2 47', 'gita 2-47']) {
      final hits = search.search(q);
      expect(hits.single.verseId, '2.47', reason: q);
      expect(hits.single.field, MatchField.reference);
    }
    expect(ids('2.73'), isNot(contains('2.73')), reason: 'no such verse');
  });

  test('Devanagari word, prefix and compound substring', () {
    expect(ids('फलेषु'), contains('2.47'));
    expect(ids('कर्मण्येवा'), contains('2.47'), reason: 'prefix of the first word');
    expect(ids('धिकार'), contains('2.47'), reason: 'inside a compound');
  });

  test('IAST and informal romanisation', () {
    for (final q in ['phaleṣu', 'phaleshu', 'phalesu', 'karmanye', 'kadachana', 'dharmakshetre']) {
      expect(ids(q), isNotEmpty, reason: q);
    }
    expect(ids('dharmakshetre').first, '1.1');
    expect(ids('phaleshu kadachana'), contains('2.47'), reason: 'all words must match');
  });

  test('Telugu script', () {
    expect(ids('ఫలేషు'), contains('2.47'));
  });

  test('English words in explanations', () {
    final hits = search.search('anxiety');
    expect(hits.map((h) => h.verseId), contains('2.47'));
    expect(hits.firstWhere((h) => h.verseId == '2.47').snippet, contains('«anxiety»'));
  });

  test('FTS syntax in user input is treated as text, not as a query', () {
    for (final q in ['"', 'AND', 'NEAR(', '*', 'a OR b', "x' --"]) {
      expect(() => search.search(q), returnsNormally, reason: q);
    }
  });

  test('empty and nonsense queries', () {
    expect(search.search('   '), isEmpty);
    expect(search.search('zzzqqq'), isEmpty);
  });

  test('IAST highlighting follows informal spelling', () {
    final parts = highlightIast('karmaṇyevādhikāraste mā phaleṣu kadācana ।', 'phaleshu');
    expect(parts.where((p) => p.$2).map((p) => p.$1), ['phaleṣu']);
    expect(parts.map((p) => p.$1).join(), 'karmaṇyevādhikāraste mā phaleṣu kadācana ।');
  });
}
