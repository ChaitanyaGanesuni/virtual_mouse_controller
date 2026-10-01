import 'dart:io';
import 'dart:typed_data';

import 'package:gita_companion/core/content/sqlite_content_repository.dart';
import 'package:sqlite3/sqlite3.dart';

/// The real content pack, built by tool/sync_content.sh (CI runs it first).
const packPath = 'assets/content/gita_content_pack.sqlite';
const manifestPath = 'assets/content/pack_manifest.json';

File requirePack() {
  final f = File(packPath);
  if (!f.existsSync()) {
    throw StateError('Content pack missing. Run tool/sync_content.sh before flutter test.');
  }
  return f;
}

SqliteContentRepository openRealRepository() =>
    SqliteContentRepository(sqlite3.open(requirePack().path, mode: OpenMode.readOnly));

/// Asset loader for ContentPackInstaller that reads the files from disk.
Future<ByteData> loadAssetFromDisk(String key) async {
  final bytes = await File(key).readAsBytes();
  return ByteData.sublistView(bytes);
}

/// A writable copy of the real pack with one sample AI record for 2.47
/// (English) and a Telugu "simple" text, for reader tests. Mirrors what
/// `gita-content build` writes for AI output.
Database openPackWithSampleAi() {
  final dir = Directory.systemTemp.createTempSync('pack_ai');
  final copy = requirePack().copySync('${dir.path}/pack.sqlite');
  final db = sqlite3.open(copy.path);
  const src = 'ai-groq-test-model-verse-explain-v1';
  db.execute(
    'INSERT INTO source (id, kind, title, author, language, license, is_ai_generated, model_id, prompt_version) '
    "VALUES ('$src', 'ai', 'AI-generated explanations (test-model)', 'test-model via groq', 'mul', "
    "'AI-generated text', 1, 'test-model', 'verse-explain-v1')",
  );
  final texts = {
    'simple': 'You have a right to your actions, never to their fruits.',
    'deep': 'Deep: the verse separates action from craving for results.',
    'practical': 'At work, give full effort and release anxiety about outcomes.',
    'story': 'A gardener waters the seed and trusts the season.',
    'child': 'Do your homework well; worrying about marks does not help.',
    'sanskrit_terms': '[{"term": "karma", "meaning": "Action, especially one\'s duty."}]',
  };
  var i = 0;
  for (final e in texts.entries) {
    db.execute('INSERT INTO verse_text VALUES (?, ?, ?, ?, ?, ?, ?)', [
      't${i++}',
      '2.47',
      src,
      e.key,
      'en',
      e.value,
      'unreviewed',
    ]);
  }
  db.execute('INSERT INTO verse_text VALUES (?, ?, ?, ?, ?, ?, ?)', [
    't-te',
    '2.47',
    src,
    'simple',
    'te',
    'కర్మ చేయడంలోనే నీకు అధికారం ఉంది.',
    'unreviewed',
  ]);
  db.execute('INSERT INTO word_meaning VALUES (?, ?, ?, ?, ?, ?, ?)', [
    'w0',
    '2.47',
    src,
    0,
    'karmaṇi',
    'en',
    'in action',
  ]);
  db.execute("UPDATE verse_fts SET explanation = ? WHERE verse_id = '2.47'", [
    '${texts['simple']} ${texts['deep']} ${texts['practical']}',
  ]);
  return db;
}
