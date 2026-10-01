import 'package:sqlite3/sqlite3.dart';

import 'content_repository.dart';
import 'models.dart';

/// [ContentRepository] backed by the read-only content pack.
///
/// The pack is small (701 verses), so chapters, speakers, sources and the
/// reading order are loaded once; verses are queried on demand.
class SqliteContentRepository implements ContentRepository {
  SqliteContentRepository(this._db) {
    _sources = {
      for (final r in _db.select('SELECT * FROM source'))
        r['id'] as String: Source(
          id: r['id'] as String,
          kind: r['kind'] as String,
          title: r['title'] as String,
          author: r['author'] as String,
          license: r['license'] as String,
          isAiGenerated: (r['is_ai_generated'] as int) == 1,
          year: r['year'] as int?,
          url: r['url'] as String?,
          modelId: r['model_id'] as String?,
          promptVersion: r['prompt_version'] as String?,
        ),
    };
    _speakers = {
      for (final r in _db.select('SELECT * FROM speaker'))
        r['id'] as String: Speaker(
          id: r['id'] as String,
          nameEn: r['name_en'] as String,
          lines: {
            'sa': r['line_sa'] as String,
            'sa-Latn': r['line_sa_latn'] as String,
            'sa-Telu': r['line_sa_telu'] as String,
          },
        ),
    };
    final names = <int, Map<String, String>>{};
    final titles = <int, String>{};
    final overviews = <int, List<ChapterText>>{};
    for (final r in _db.select('SELECT * FROM chapter_text')) {
      final n = r['chapter'] as int;
      final kind = r['kind'] as String;
      if (kind == 'name') names.putIfAbsent(n, () => {})[r['language'] as String] = r['body'] as String;
      if (kind == 'title' && r['language'] == 'en') titles[n] = r['body'] as String;
      if (kind == 'summary' || kind == 'theme') {
        overviews
            .putIfAbsent(n, () => [])
            .add(
              ChapterText(
                kind: kind,
                language: r['language'] as String,
                body: r['body'] as String,
                sourceId: r['source_id'] as String,
                reviewStatus: ReviewStatus.parse(r['review_status'] as String),
              ),
            );
      }
    }
    _chapters = [
      for (final r in _db.select('SELECT * FROM chapter ORDER BY number'))
        Chapter(
          number: r['number'] as int,
          nameSa: r['name_sa'] as String,
          verseCount: r['verse_count'] as int,
          names: names[r['number'] as int] ?? const {},
          titleEn: titles[r['number'] as int] ?? '',
          texts: overviews[r['number'] as int] ?? const [],
        ),
    ];
    _order = [for (final r in _db.select('SELECT id FROM verse ORDER BY chapter, verse')) r['id'] as String];
    _canonical = [
      for (final r in _db.select('SELECT id FROM verse WHERE is_canonical = 1 ORDER BY chapter, verse'))
        r['id'] as String,
    ];
    _index = {for (var i = 0; i < _order.length; i++) _order[i]: i};
  }

  final Database _db;
  late final Map<String, Source> _sources;
  late final Map<String, Speaker> _speakers;
  late final List<Chapter> _chapters;
  late final List<String> _order;
  late final List<String> _canonical;
  late final Map<String, int> _index;

  @override
  List<Chapter> chapters() => _chapters;

  @override
  Chapter chapter(int number) => _chapters.firstWhere(
    (c) => c.number == number,
    orElse: () => throw ArgumentError.value(number, 'number', 'no such chapter'),
  );

  @override
  List<Verse> versesOf(int chapter) {
    final rows = _db.select('SELECT * FROM verse WHERE chapter = ? ORDER BY verse', [chapter]);
    final texts = _textsFor(
      'SELECT vt.* FROM verse_text vt JOIN verse v ON v.id = vt.verse_id WHERE v.chapter = ?',
      [chapter],
    );
    final words = _wordsFor(
      'SELECT wm.* FROM word_meaning wm JOIN verse v ON v.id = wm.verse_id WHERE v.chapter = ?',
      [chapter],
    );
    return [for (final r in rows) _verse(r, texts[r['id']] ?? const [], words[r['id']] ?? const [])];
  }

  @override
  Verse? verse(String id) {
    final rows = _db.select('SELECT * FROM verse WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    final texts = _textsFor('SELECT * FROM verse_text WHERE verse_id = ?', [id]);
    final words = _wordsFor('SELECT * FROM word_meaning WHERE verse_id = ?', [id]);
    return _verse(rows.first, texts[id] ?? const [], words[id] ?? const []);
  }

  @override
  List<String> readingOrder() => _order;

  @override
  String? previousVerseId(String id) {
    final i = _index[id];
    return (i == null || i == 0) ? null : _order[i - 1];
  }

  @override
  String? nextVerseId(String id) {
    final i = _index[id];
    return (i == null || i == _order.length - 1) ? null : _order[i + 1];
  }

  @override
  Source? source(String id) => _sources[id];

  @override
  List<Speaker> speakers() => _speakers.values.toList();

  @override
  List<Source> sources() => _sources.values.toList();

  @override
  Verse verseOfTheDay(DateTime date) => verse(_canonical[dayIndex(date, _canonical.length)])!;

  Map<String, List<VerseText>> _textsFor(String sql, List<Object?> args) {
    final out = <String, List<VerseText>>{};
    for (final r in _db.select(sql, args)) {
      out
          .putIfAbsent(r['verse_id'] as String, () => [])
          .add(
            VerseText(
              id: r['id'] as String,
              kind: r['kind'] as String,
              language: r['language'] as String,
              body: r['body'] as String,
              sourceId: r['source_id'] as String,
              reviewStatus: ReviewStatus.parse(r['review_status'] as String),
            ),
          );
    }
    return out;
  }

  Map<String, List<WordMeaning>> _wordsFor(String sql, List<Object?> args) {
    final out = <String, List<WordMeaning>>{};
    for (final r in _db.select('$sql ORDER BY verse_id, source_id, language, position', args)) {
      out
          .putIfAbsent(r['verse_id'] as String, () => [])
          .add(
            WordMeaning(
              word: r['word_sa'] as String,
              meaning: r['meaning'] as String,
              language: r['language'] as String,
              sourceId: r['source_id'] as String,
            ),
          );
    }
    return out;
  }

  Verse _verse(Row r, List<VerseText> texts, List<WordMeaning> words) => Verse(
    id: r['id'] as String,
    chapter: r['chapter'] as int,
    verse: r['verse'] as int,
    isCanonical: (r['is_canonical'] as int) == 1,
    sanskrit: r['sanskrit'] as String,
    sourceId: r['source_id'] as String,
    reviewStatus: ReviewStatus.parse(r['review_status'] as String),
    speaker: _speakers[r['speaker']],
    texts: texts,
    wordMeanings: words,
  );
}

/// Maps a calendar date to an index in [0, length). Uses the date only (not
/// the time or timezone offset) and a fixed integer hash, so every device
/// shows the same verse on the same date and consecutive days jump around
/// the text instead of walking through it.
int dayIndex(DateTime date, int length) {
  final days =
      DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  // 32-bit integer mix (splitmix-style), stable across platforms.
  var x = (days * 0x9E3779B1) & 0xFFFFFFFF;
  x = ((x ^ (x >> 16)) * 0x85EBCA6B) & 0xFFFFFFFF;
  x = ((x ^ (x >> 13)) * 0xC2B2AE35) & 0xFFFFFFFF;
  x = x ^ (x >> 16);
  return x % length;
}
