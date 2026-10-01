import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/core/audio/audio_cache.dart';
import 'package:gita_companion/core/audio/manifest.dart';
import 'package:gita_companion/core/audio/synthesizer.dart';
import 'package:gita_companion/core/audio/text_prep.dart';
import 'package:gita_companion/core/audio/tts_provider.dart';
import 'package:gita_companion/core/content/models.dart';
import 'package:gita_companion/core/db/user_database.dart';

import 'support/audio_fakes.dart';
import 'support/pack.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('text preparation', () {
    test('verse references are spoken as chapter and verse', () {
      expect(normalizeForSpeech('As 2.47 teaches.', 'en'), 'As chapter 2, verse 47 teaches.');
      expect(normalizeForSpeech('2.47 చూడండి', 'te'), 'అధ్యాయం 2, శ్లోకం 47 చూడండి');
      expect(normalizeForSpeech('version 1.2.3', 'en'), 'version 1.2.3');
      expect(normalizeForSpeech('Compare 3.19.', 'en'), 'Compare chapter 3, verse 19.');
    });

    test('dandas become pauses; Sanskrit numbers are untouched', () {
      expect(normalizeForSpeech('मा फलेषु कदाचन ।', 'sa'), 'मा फलेषु कदाचन ,');
      expect(normalizeForSpeech('सर्वशः ॥', 'sa'), 'सर्वशः .');
    });

    test('long text is chunked at sentence boundaries without losing words', () {
      final text = List.generate(40, (i) => 'Sentence number $i has a few words in it.').join(' ');
      final chunks = chunkText(text);
      expect(chunks.length, greaterThan(3));
      expect(chunks.every((c) => c.length <= maxChunkChars), isTrue);
      expect(chunks.every((c) => c.endsWith('.')), isTrue, reason: 'breaks fall between sentences');
      expect(chunks.join(' ').split(' '), text.split(' '));
    });

    test('a single very long sentence is split at commas, then between words', () {
      final longSentence = '${List.generate(60, (i) => 'clause $i').join(', ')}.';
      final chunks = chunkText(longSentence);
      expect(chunks.every((c) => c.length <= maxChunkChars), isTrue);
      expect(chunks.join(' ').split(' '), longSentence.split(' '));
      final noCommas = List.generate(200, (i) => 'word$i').join(' ');
      expect(chunkText(noCommas).every((c) => c.length <= maxChunkChars), isTrue);
    });

    test('decimals stay inside their sentence', () {
      expect(splitSentences('Play at 1.5 speed. Then rest.'), ['Play at 1.5 speed.', 'Then rest.']);
    });

    test('a tiny trailing chunk is merged', () {
      final text = '${'A sentence of moderate length here. ' * 8}Ok.';
      expect(chunkText(text).last.length, greaterThan(minChunkChars));
    });
  });

  group('audio hash', () {
    String h({String text = 'x', String provider = 'device', String version = '1', double rate = 1.0}) =>
        audioHash(
          text: text,
          language: 'en',
          provider: provider,
          providerVersion: version,
          voice: 'v',
          rate: rate,
        );

    test('identical requests share a hash; whitespace is normalised', () {
      expect(h(text: 'a  b'), h(text: 'a b'));
    });

    test('provider version and synthesis rate change the hash', () {
      expect(h(version: '2'), isNot(h()));
      expect(h(rate: 0.7), isNot(h()));
      expect(h(provider: 'other'), isNot(h()));
    });
  });

  group('manifests', () {
    final repo = openRealRepository();
    const b = ManifestBuilder();

    test('recitation: speaker heading then one chunk per half-verse', () {
      final m = b.recitation(repo.verse('2.11')!);
      expect(m.chunks.first.text, 'श्रीभगवानुवाच');
      expect(m.chunks[1].displayText, endsWith(' ।'), reason: 'the screen shows the verse as written');
      expect(m.chunks[1].text, endsWith(' ,'), reason: 'the engine gets a pause instead of a danda');
      expect(m.chunks.length, 1 + repo.verse('2.11')!.sanskrit.split('\n').length);
      expect(m.chunks.every((c) => c.kind == ChunkKind.recitation && c.language == 'sa'), isTrue);
      expect(b.recitation(repo.verse('2.11')!, slow: true).chunks.first.rate, 0.7);
      expect(b.recitation(repo.verse('2.11')!, slow: true).id, isNot(m.id));
    });

    test('chapter manifest covers every verse in order, with stable ids', () {
      final verses = repo.versesOf(2);
      final m = b.chapter(2, verses, explanationFor: (_) => null);
      expect(m.chunks.map((c) => c.verseId).toSet().length, 72);
      expect(m.chunks.first.verseId, '2.1');
      expect(m.chunks.last.verseId, '2.72');
      expect(
        b.chapter(2, verses, explanationFor: (_) => null).chunks.map((c) => c.id),
        m.chunks.map((c) => c.id),
      );
    });

    test('verse with explanation appends speech chunks', () {
      const e = VerseText(
        id: 'x',
        kind: 'simple',
        language: 'en',
        sourceId: 's',
        reviewStatus: ReviewStatus.unreviewed,
        body: 'You have a right to action. Compare 3.19.',
      );
      final m = b.verseWithExplanation(repo.verse('2.47')!, e);
      final speech = m.chunks.where((c) => c.kind == ChunkKind.speech).toList();
      expect(speech.single.text, 'You have a right to action. Compare chapter 3, verse 19.');
      expect(m.indexOfVerse('2.47'), 0);
    });
  });

  group('cache and synthesizer', () {
    late Directory dir;
    late UserDatabase db;
    late AudioCache cache;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('audio');
      db = UserDatabase.memory();
      cache = AudioCache(directory: dir, db: db, maxBytes: 1000);
    });
    tearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    const chunk = AudioChunk(
      id: 'm/c0000',
      text: 'Hello there.',
      language: 'en',
      kind: ChunkKind.speech,
      section: 'simple',
    );

    test('second request for the same chunk is served from the cache', () async {
      final tts = FakeTtsProvider();
      final s = AudioSynthesizer(providers: [tts], cache: cache, voicePrefs: () => {});
      final a = await s.fileFor(chunk);
      final b = await s.fileFor(chunk);
      expect(a.file.path, b.file.path);
      expect(tts.calls, hasLength(1));
    });

    test('preferred voice wins; Indian locale preferred otherwise', () async {
      final tts = FakeTtsProvider(
        voices: const [
          Voice(id: 'us', name: 'US', locale: 'en-US'),
          Voice(id: 'in', name: 'IN', locale: 'en-IN'),
          Voice(id: 'gb', name: 'GB', locale: 'en-GB'),
        ],
      );
      expect(
        (await AudioSynthesizer(providers: [tts], cache: cache, voicePrefs: () => {}).choose(chunk)).voice.id,
        'in',
      );
      final s = AudioSynthesizer(providers: [tts], cache: cache, voicePrefs: () => {'en': 'gb'});
      expect((await s.choose(chunk)).voice.id, 'gb');
    });

    test('Sanskrit falls back to a Hindi voice and is marked approximate', () async {
      const sa = AudioChunk(
        id: 'r/c0',
        text: 'धर्मक्षेत्रे',
        language: 'sa',
        kind: ChunkKind.recitation,
        section: 'recitation',
      );
      final s = AudioSynthesizer(providers: [FakeTtsProvider()], cache: cache, voicePrefs: () => {});
      final c = await s.choose(sa);
      expect(c.voice.id, 'hi-voice');
      expect(c.approximate, isTrue);
      final native = FakeTtsProvider(
        voices: const [Voice(id: 'sa', name: 'sa', locale: 'sa-IN')],
      );
      final c2 = await AudioSynthesizer(providers: [native], cache: cache, voicePrefs: () => {}).choose(sa);
      expect(c2.approximate, isFalse);
    });

    test('no voice for a language is reported, not silently skipped', () async {
      final s = AudioSynthesizer(
        providers: [
          FakeTtsProvider(
            voices: const [Voice(id: 'e', name: 'e', locale: 'en-IN')],
          ),
        ],
        cache: cache,
        voicePrefs: () => {},
      );
      const te = AudioChunk(
        id: 't/c0',
        text: 'నమస్తే',
        language: 'te',
        kind: ChunkKind.speech,
        section: 'simple',
      );
      expect(() => s.choose(te), throwsA(isA<NoVoiceAvailable>()));
    });

    test('LRU eviction keeps the cache under its limit and never evicts pinned files', () async {
      var t = DateTime(2026);
      final c = AudioCache(
        directory: dir,
        db: db,
        maxBytes: 250,
        clock: () => t = t.add(const Duration(minutes: 1)),
      );
      Future<void> add(String hash) async {
        final f = c.fileFor(hash)..writeAsBytesSync(List.filled(100, 1));
        await c.put(hash, f, provider: 'p', voice: 'v');
      }

      final h = [for (var i = 0; i < 4; i++) i.toString() * 64];
      await add(h[0]);
      await c.pin(h[0]);
      await add(h[1]);
      await add(h[2]); // over the limit: h[1] (oldest unpinned) goes
      expect(await c.get(h[0]), isNotNull);
      expect(await c.get(h[1]), isNull);
      await add(h[3]);
      expect(await c.totalBytes(), lessThanOrEqualTo(250));
      expect(await c.get(h[0]), isNotNull, reason: 'pinned (downloaded) audio is kept');
    });

    test('a file deleted behind the cache is treated as a miss', () async {
      final tts = FakeTtsProvider();
      final s = AudioSynthesizer(providers: [tts], cache: cache, voicePrefs: () => {});
      final first = await s.fileFor(chunk);
      first.file.deleteSync();
      await s.fileFor(chunk);
      expect(tts.calls, hasLength(2));
    });
  });
}
