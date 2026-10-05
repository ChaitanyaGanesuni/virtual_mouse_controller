import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/core/search/search_service.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:yaml/yaml.dart';

import 'support/pack.dart';

/// The app's offline search measured on the same golden set as the server
/// (content/eval/golden.yaml, see content/gita_content/evaluate.py). Fails
/// when a score drops below its floor; the phase targets are printed.
const k = 8;
const targets = {'hit@8': 0.85, 'recall@8': 0.60};
const floors = {
  'en': {'hit@8': 0.87, 'recall@8': 0.55},
  'te': {'hit@8': 0.93, 'recall@8': 0.70},
};

void main() {
  test('golden set: hit@8 and recall@8 stay above their floors', () {
    final db = sqlite3.open(requirePack().path, mode: OpenMode.readOnly);
    addTearDown(db.close);
    final ids = {for (final r in db.select('SELECT id FROM verse')) r['id'] as String};
    final search = SqliteSearchService(db, verseExists: ids.contains);
    final golden =
        (loadYaml(File('../content/eval/golden.yaml').readAsStringSync()) as YamlMap)['questions']
            as YamlList;

    final byLang = <String, List<(bool, double, double)>>{};
    for (final g in golden.cast<YamlMap>()) {
      final expected = (g['expect'] as YamlList).cast<String>().toSet();
      final got = search.search(g['q'] as String, limit: k).map((h) => h.verseId).toList();
      final found = got.toSet().intersection(expected).length;
      final rank = got.indexWhere(expected.contains);
      byLang.putIfAbsent(g['lang'] as String? ?? 'en', () => []).add((
        found > 0,
        found / (expected.length < k ? expected.length : k),
        rank < 0 ? 0.0 : 1 / (rank + 1),
      ));
    }

    final problems = <String>[];
    for (final MapEntry(key: lang, value: rs) in byLang.entries) {
      double avg(double Function((bool, double, double)) f) => rs.map(f).reduce((a, b) => a + b) / rs.length;
      final stats = {
        'hit@8': avg((r) => r.$1 ? 1.0 : 0.0),
        'recall@8': avg((r) => r.$2),
        'mrr': avg((r) => r.$3),
      };
      final shown = stats.map((m, v) => MapEntry(m, v.toStringAsFixed(3)));
      final missed = [
        for (final t in targets.entries)
          if (stats[t.key]! < t.value) t.key,
      ];
      // ignore: avoid_print
      print('$lang (${rs.length} questions): $shown; targets ${missed.isEmpty ? 'met' : 'NOT met: $missed'}');
      for (final f in floors[lang]!.entries) {
        if (stats[f.key]! < f.value) problems.add('$lang ${f.key} ${stats[f.key]} < ${f.value}');
      }
    }
    expect(problems, isEmpty);
  });
}
