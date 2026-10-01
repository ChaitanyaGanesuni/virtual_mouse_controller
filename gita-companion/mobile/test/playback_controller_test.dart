import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/core/audio/audio_cache.dart';
import 'package:gita_companion/core/audio/listening_progress.dart';
import 'package:gita_companion/core/audio/manifest.dart';
import 'package:gita_companion/core/audio/playback_controller.dart';
import 'package:gita_companion/core/audio/synthesizer.dart';
import 'package:gita_companion/core/db/user_database.dart';

import 'support/audio_fakes.dart';

AudioManifest manifest({int verses = 3, int chunksPerVerse = 2, int repeat = 1, String id = 'm'}) {
  final chunks = <AudioChunk>[];
  for (var v = 1; v <= verses; v++) {
    for (var c = 0; c < chunksPerVerse; c++) {
      chunks.add(
        AudioChunk(
          id: '$id/c${chunks.length.toString().padLeft(4, '0')}',
          // 140 characters: estimated at exactly 10 s, matching the fake player.
          text: 'Verse $v part $c. '.padRight(140, 'x'),
          language: 'en',
          kind: ChunkKind.speech,
          section: 'simple',
          verseId: '2.$v',
        ),
      );
    }
  }
  return AudioManifest(id: id, title: 'test', chapter: 2, chunks: chunks, repeat: repeat);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dir;
  late UserDatabase db;
  late FakeTtsProvider tts;
  late FakeBackend backend;
  late ListeningProgressRepository progress;
  late PlaybackController player;
  late DateTime now;

  PlaybackController build({FakeTtsProvider? provider}) {
    final cache = AudioCache(directory: dir, db: db);
    return PlaybackController(
      backend: backend,
      synthesizer: AudioSynthesizer(providers: [provider ?? tts], cache: cache, voicePrefs: () => {}),
      cache: cache,
      progress: progress,
      clock: () => now,
    );
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('player');
    db = UserDatabase.memory();
    tts = FakeTtsProvider();
    backend = FakeBackend();
    progress = ListeningProgressRepository(db);
    now = DateTime(2026, 10, 1, 7);
    player = build();
  });

  tearDown(() async {
    player.dispose();
    await db.close();
    dir.deleteSync(recursive: true);
  });

  String playing() => backend.loaded.last.split(':').last.split(' x').first.trim();

  test('plays chunks in order and prefetches ahead', () async {
    await player.open(manifest());
    await settle();
    expect(player.state.status, PlayerStatus.playing);
    expect(playing(), 'Verse 1 part 0.');
    expect(
      tts.calls.map((c) => c.text.split(' x').first.trim()),
      containsAll(['Verse 1 part 1.', 'Verse 2 part 0.']),
      reason: 'next two chunks are prepared in the background',
    );

    await backend.finish();
    expect(playing(), 'Verse 1 part 1.');
    expect(player.state.chunk!.verseId, '2.1');
  });

  test('finishes, saves completion, and does not resume a finished manifest', () async {
    final m = manifest(verses: 1);
    await player.open(m);
    await backend.finish();
    await backend.finish();
    expect(player.state.status, PlayerStatus.finished);
    expect((await progress.load(m.id))!.completed, isTrue);
    expect(await progress.latest(), isNull, reason: 'finished items do not appear in Continue listening');
  });

  test('Repeat ×3 plays the whole manifest three times', () async {
    await player.open(manifest(verses: 1, chunksPerVerse: 1, repeat: 3));
    await backend.finish();
    expect(player.state.round, 2);
    await backend.finish();
    expect(player.state.round, 3);
    await backend.finish();
    expect(player.state.status, PlayerStatus.finished);
    expect(backend.loaded, hasLength(3));
    expect(tts.calls, hasLength(1), reason: 'repeats come from the cache');
  });

  test('global timeline: total, elapsed and seeking across chunks', () async {
    await player.open(manifest()); // 6 chunks × 10 s (fake durations)
    await settle();
    backend.position = const Duration(seconds: 4);
    await player.seekTo(const Duration(seconds: 35));
    expect(player.state.index, 3);
    expect(backend.position, const Duration(seconds: 5));
    expect(player.state.elapsed, const Duration(seconds: 35));
  });

  test('skip ±15 s crosses chunk boundaries and clamps at zero', () async {
    await player.open(manifest());
    await settle();
    backend.position = const Duration(seconds: 8);
    await player.skip(const Duration(seconds: 15));
    expect(player.state.index, 2);
    expect(backend.position, const Duration(seconds: 3));
    await player.skip(const Duration(seconds: -60));
    expect(player.state.index, 0);
    expect(backend.position, Duration.zero);
  });

  test('next and previous verse jump to verse boundaries', () async {
    await player.open(manifest());
    await settle();
    await player.nextVerse();
    expect(player.state.chunk!.verseId, '2.2');
    expect(player.state.index, 2);
    await player.nextVerse();
    expect(player.state.chunk!.verseId, '2.3');
    await player.previousVerse(); // at the start of 2.3 → back to 2.2
    expect(player.state.chunk!.verseId, '2.2');
    backend.position = const Duration(seconds: 6);
    await player.previousVerse(); // well into 2.2 → restart 2.2
    expect(player.state.index, 2);
  });

  test('speed is applied by the player, not re-synthesized', () async {
    await player.open(manifest());
    await settle();
    final before = tts.calls.length;
    await player.setSpeed(1.5);
    expect(backend.speed, 1.5);
    expect(tts.calls.length, before);
    expect(() => player.setSpeed(3.0), throwsArgumentError);
  });

  test('pause saves chapter, verse, chunk and position; reopening resumes there', () async {
    final m = manifest();
    await player.open(m);
    await settle();
    await backend.finish(); // chunk 1
    await backend.finish(); // chunk 2 (verse 2.2)
    backend.position = const Duration(seconds: 7);
    await player.setSpeed(1.25);
    await player.pause();

    final saved = (await progress.load(m.id))!;
    expect((saved.chapter, saved.verseId, saved.audioChunkId), (2, '2.2', 'm/c0002'));
    expect(saved.positionSeconds, 7);
    expect(saved.speed, 1.25);

    // App restarted: a new controller resumes from the saved state.
    player.dispose();
    backend = FakeBackend();
    player = build();
    await player.open(m);
    await settle();
    expect(player.state.index, 2);
    expect(backend.position, const Duration(seconds: 7));
    expect(backend.speed, 1.25);
    expect((await progress.latest())!.manifestId, m.id);
  });

  test('progress is saved periodically while playing', () async {
    final m = manifest();
    await player.open(m);
    await settle();
    backend.position = const Duration(seconds: 3);
    now = now.add(const Duration(seconds: 6));
    await Future<void>.delayed(const Duration(milliseconds: 600)); // one ticker period
    await settle();
    expect((await progress.load(m.id))?.positionSeconds, 3);
  });

  test('a chunk that keeps failing is skipped so playback continues', () async {
    final failing = FakeTtsProvider(failTexts: {'Verse 1 part 1. '.padRight(140, 'x')});
    player.dispose();
    player = build(provider: failing);
    await player.open(manifest());
    await backend.finish();
    await settle();
    expect(playing(), 'Verse 2 part 0.');
    expect(player.state.status, PlayerStatus.playing);
    expect(
      failing.calls.where((c) => c.text.startsWith('Verse 1 part 1.')).length,
      greaterThanOrEqualTo(2),
      reason: 'retried once before skipping',
    );
  });

  test('missing voice pauses with an explanation instead of failing silently', () async {
    player.dispose();
    player = build(provider: FakeTtsProvider(voices: const []));
    await player.open(manifest());
    await settle();
    expect(player.state.status, PlayerStatus.paused);
    expect(player.state.error, 'no-voice:en');
  });

  test('opening another manifest saves the previous position', () async {
    final a = manifest(id: 'a');
    await player.open(a);
    await settle();
    backend.position = const Duration(seconds: 4);
    await player.open(manifest(id: 'b'));
    expect((await progress.load('a'))!.positionSeconds, 4);
  });
}
