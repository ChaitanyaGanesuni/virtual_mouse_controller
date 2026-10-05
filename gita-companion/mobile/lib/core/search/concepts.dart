/// Dart port of query understanding in `gita_content/concepts.py`
/// (tokens, normalize_en, telugu_stem, ConceptIndex.match). Must produce
/// exactly the outputs in content/tests/query_vectors.json (checked by
/// test/concepts_test.dart). Input is expected in Unicode NFC, which is what
/// keyboards produce.
library;

import 'package:sqlite3/sqlite3.dart';

import 'romanize.dart';

const relatedFactor = 0.35;
const weakTermFactor = 0.35;

final _token = RegExp(r'(?:\p{L}|[ऀ-ൿ])+', unicode: true);
final _possessive = RegExp(r"'s\b");
const _teSuffixes = ['ాలు', 'లు', 'ము', 'ం', 'ు'];

// Latin letters with diacritics → plain letters (yajña → yajna, Pârtha → partha).
const _from = 'āáàâäãīíìîïūúùûüēéèêëōóòôöṛṝḷḹṅñṇṭḍśṣṃṁḥçṯḏ';
const _to = 'aaaaaaiiiiiuuuuueeeeeooooorrllnnntdssmmhctd';
final Map<String, String> _fold = {for (var i = 0; i < _from.length; i++) _from[i]: _to[i]};

String _foldLatin(String s) {
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(_fold[ch] ?? ch);
  }
  return b.toString();
}

List<String> tokens(String text) {
  var s = _foldLatin(text.toLowerCase().replaceAll('’', "'"));
  s = s.replaceAll(_possessive, '');
  return [for (final m in _token.allMatches(s)) m.group(0)!];
}

bool isTelugu(String token) => token.runes.any((r) => r >= 0x0C00 && r <= 0x0C7F);

String stemEn(String w) {
  if (w.length <= 3) return w;
  if (w.endsWith('ies') && w.length > 4) return '${w.substring(0, w.length - 3)}y';
  if (w.endsWith('ied') && w.length > 4) return '${w.substring(0, w.length - 3)}y';
  if (w.endsWith('ness') && w.length > 6) return w.substring(0, w.length - 4);
  String undouble(String x) =>
      x.length > 2 && x[x.length - 1] == x[x.length - 2] && !'lsz'.contains(x[x.length - 1])
      ? x.substring(0, x.length - 1)
      : x;
  if (w.endsWith('ing') && w.length > 5) return undouble(w.substring(0, w.length - 3));
  if (w.endsWith('ed') && w.length > 4) return undouble(w.substring(0, w.length - 2));
  if (w.endsWith('ly') && w.length > 5) return w.substring(0, w.length - 2);
  if (w.endsWith('sses') || w.endsWith('ches') || w.endsWith('shes') || w.endsWith('xes')) {
    return w.substring(0, w.length - 2);
  }
  if (w.endsWith('s') && !w.endsWith('ss') && !w.endsWith('us') && !w.endsWith('is')) {
    return w.substring(0, w.length - 1);
  }
  return w;
}

List<String> normalizeEn(String text) => [
  for (final t in tokens(text))
    if (!isTelugu(t)) stemEn(t),
];

String teluguStem(String term) {
  for (final suf in _teSuffixes) {
    if (term.endsWith(suf) && term.length - suf.length >= 2) {
      return term.substring(0, term.length - suf.length);
    }
  }
  return term;
}

bool _matches(List<String> key, List<String> query, String language) {
  if (key.isEmpty || key.length > query.length) return false;
  for (var i = 0; i <= query.length - key.length; i++) {
    var ok = true;
    for (var j = 0; j < key.length; j++) {
      final q = query[i + j], k = key[j];
      if (language == 'te' ? !q.startsWith(k) : q != k) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

typedef TermKey = ({String language, List<String> words});

class ConceptEntry {
  ConceptEntry({
    required this.id,
    required this.termSa,
    required this.nameEn,
    required this.nameTe,
    this.definition,
    this.strong = const [],
    this.weak = const [],
    this.related = const [],
    this.verses = const {},
  });

  final String id;
  final String termSa;
  final String nameEn;
  final String nameTe;
  final String? definition;
  final List<TermKey> strong;
  final List<TermKey> weak;
  final List<String> related;

  /// Verse id → link weight (0-1; the concept's best verse is 1).
  final Map<String, double> verses;

  String name(String language) => language == 'te' ? nameTe : nameEn;
}

/// The concept index read from the content pack (schema v3).
class ConceptIndex {
  ConceptIndex(this.entries) : byId = {for (final e in entries) e.id: e};

  final List<ConceptEntry> entries;
  final Map<String, ConceptEntry> byId;

  factory ConceptIndex.fromDb(Database db) {
    final names = <String, Map<String, (String, String?)>>{};
    for (final r in db.select('SELECT concept_id, language, name, definition FROM concept_text')) {
      (names[r['concept_id'] as String] ??= {})[r['language'] as String] = (
        r['name'] as String,
        r['definition'] as String?,
      );
    }
    final strong = <String, List<TermKey>>{}, weak = <String, List<TermKey>>{};
    for (final r in db.select(
      'SELECT concept_id, language, term_key, weak FROM concept_term ORDER BY rowid',
    )) {
      final key = (language: r['language'] as String, words: (r['term_key'] as String).split(' '));
      ((r['weak'] as int) == 1 ? weak : strong).putIfAbsent(r['concept_id'] as String, () => []).add(key);
    }
    final related = <String, List<String>>{};
    for (final r in db.select('SELECT concept_id, related_id FROM concept_related ORDER BY rowid')) {
      (related[r['concept_id'] as String] ??= []).add(r['related_id'] as String);
    }
    final verses = <String, Map<String, double>>{};
    for (final r in db.select('SELECT concept_id, verse_id, weight FROM verse_concept')) {
      (verses[r['concept_id'] as String] ??= {})[r['verse_id'] as String] = (r['weight'] as num).toDouble();
    }
    return ConceptIndex([
      for (final r in db.select('SELECT id, term_sa FROM concept ORDER BY rowid'))
        ConceptEntry(
          id: r['id'] as String,
          termSa: r['term_sa'] as String? ?? '',
          nameEn: names[r['id']]?['en']?.$1 ?? r['id'] as String,
          nameTe: names[r['id']]?['te']?.$1 ?? names[r['id']]?['en']?.$1 ?? r['id'] as String,
          definition: names[r['id']]?['en']?.$2,
          strong: strong[r['id']] ?? const [],
          weak: weak[r['id']] ?? const [],
          related: related[r['id']] ?? const [],
          verses: verses[r['id']] ?? const {},
        ),
    ]);
  }

  /// Concepts the query is about: 1.0 for a direct match, [relatedFactor] for
  /// concepts related to a direct match, [weakTermFactor] for a concept named
  /// only by a generic word ("god", "work").
  Map<String, double> match(String query) {
    final raw = tokens(query);
    final en = [
      for (final t in raw)
        if (!isTelugu(t)) stemEn(t),
    ];
    final looseQ = loose(raw.where((t) => !isTelugu(t)).join(' '))
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    final te = raw.where(isTelugu).toList();

    bool hit(List<TermKey> keys, {required bool weak}) {
      for (final k in keys) {
        final q = k.language == 'te' ? te : en;
        if (_matches(k.words, q, k.language)) return true;
        if (k.language == 'en' && !weak && _matches(k.words, looseQ, 'en')) return true;
      }
      return false;
    }

    final out = <String, double>{};
    final direct = [
      for (final e in entries)
        if (hit(e.strong, weak: false)) e.id,
    ];
    for (final id in direct) {
      out[id] = 1.0;
    }
    for (final id in direct) {
      for (final r in byId[id]!.related) {
        out.putIfAbsent(r, () => relatedFactor);
      }
    }
    for (final e in entries) {
      if (!out.containsKey(e.id) && hit(e.weak, weak: true)) out[e.id] = weakTermFactor;
    }
    return out;
  }
}
