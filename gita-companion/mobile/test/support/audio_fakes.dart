import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:gita_companion/app/providers.dart';
import 'package:gita_companion/core/audio/audio_cache.dart';
import 'package:gita_companion/core/audio/listening_progress.dart';
import 'package:gita_companion/core/audio/playback_controller.dart';
import 'package:gita_companion/core/audio/tts_provider.dart';
import 'package:gita_companion/core/db/user_database.dart';

/// Writes a small fake audio file per request and records every call.
class FakeTtsProvider implements TtsProvider {
  FakeTtsProvider({this.id = 'fake', this.version = '1', List<Voice>? voices, this.failTexts = const {}})
    : voices =
          voices ??
          const [
            Voice(id: 'en-voice', name: 'English', locale: 'en-IN'),
            Voice(id: 'te-voice', name: 'Telugu', locale: 'te-IN'),
            Voice(id: 'hi-voice', name: 'Hindi', locale: 'hi-IN'),
          ];

  @override
  final String id;
  @override
  final String version;
  final List<Voice> voices;

  /// Texts whose synthesis fails (to test skipping).
  final Set<String> failTexts;
  final List<SynthesisRequest> calls = [];

  @override
  TtsCapabilities get capabilities =>
      const TtsCapabilities(local: true, streaming: false, maxChars: 4000, nativeSanskrit: false);

  @override
  Future<List<Voice>> getVoices() async => voices;

  @override
  Future<Set<String>> getSupportedLanguages() async => {for (final v in voices) v.language};

  @override
  Future<void> synthesizeToFile(SynthesisRequest request, File out) async {
    calls.add(request);
    if (failTexts.contains(request.text)) throw TtsException('scripted failure');
    await out.writeAsString('AUDIO:${request.voice.id}:${request.rate}:${request.text}');
  }
}

/// A player whose clock the test drives. Each file "lasts" 10 seconds
/// unless [durationOf] says otherwise.
class FakeBackend implements AudioBackend {
  FakeBackend({this.durationOf});

  final Duration Function(File)? durationOf;
  final _completed = StreamController<void>.broadcast();
  final List<String> loaded = [];
  File? current;
  bool playing = false;
  double speed = 1.0;
  Duration _position = Duration.zero;

  @override
  Future<Duration?> setFile(File file) async {
    current = file;
    loaded.add(file.readAsStringSync());
    _position = Duration.zero;
    return durationOf?.call(file) ?? const Duration(seconds: 10);
  }

  @override
  Future<void> play() async => playing = true;

  @override
  Future<void> pause() async => playing = false;

  @override
  Future<void> stop() async {
    playing = false;
    _position = Duration.zero;
  }

  @override
  Future<void> seek(Duration position) async => _position = position;

  @override
  Future<void> setSpeed(double s) async => speed = s;

  @override
  Duration get position => _position;

  set position(Duration p) => _position = p;

  @override
  Stream<void> get completed => _completed.stream;

  /// Simulates the current file reaching its end.
  Future<void> finish() async {
    _completed.add(null);
    await settle();
  }
}

/// Lets queued async work (database writes, synthesis, prefetch) finish.
Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Riverpod overrides that give widget tests a working audio stack made of
/// fakes (in-memory database, temp cache directory, fake TTS and player).
class TestAudio {
  TestAudio({FakeTtsProvider? tts})
    : tts = tts ?? FakeTtsProvider(),
      backend = FakeBackend(),
      db = UserDatabase.memory(),
      dir = Directory.systemTemp.createTempSync('audio_test');

  final FakeTtsProvider tts;
  final FakeBackend backend;
  final UserDatabase db;
  final Directory dir;

  List<Override> get overrides => [
    ttsProvidersProvider.overrideWithValue([tts]),
    audioBackendProvider.overrideWithValue(backend),
    audioCacheProvider.overrideWithValue(AudioCache(directory: dir, db: db)),
    listeningProgressProvider.overrideWithValue(ListeningProgressRepository(db)),
  ];
}
