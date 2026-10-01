import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart' as ja;

import 'playback_controller.dart';

/// [AudioBackend] on just_audio (ExoPlayer on Android). Speed changes keep
/// the pitch, so 1.5× still sounds natural.
class JustAudioBackend implements AudioBackend {
  JustAudioBackend([ja.AudioPlayer? player]) : _player = player ?? ja.AudioPlayer() {
    _sub = _player.playerStateStream.listen((s) {
      if (s.processingState == ja.ProcessingState.completed) _completed.add(null);
    });
  }

  final ja.AudioPlayer _player;
  final _completed = StreamController<void>.broadcast();
  late final StreamSubscription<ja.PlayerState> _sub;

  @override
  Future<Duration?> setFile(File file) => _player.setFilePath(file.path);

  @override
  Future<void> play() async {
    // play() completes only when playback stops; do not wait for it.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Duration get position => _player.position;

  @override
  Stream<void> get completed => _completed.stream;

  Future<void> dispose() async {
    await _sub.cancel();
    await _player.dispose();
  }
}
