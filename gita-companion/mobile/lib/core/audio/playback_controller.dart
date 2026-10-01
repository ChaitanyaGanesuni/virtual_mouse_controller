import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'audio_cache.dart';
import 'listening_progress.dart';
import 'manifest.dart';
import 'synthesizer.dart';

/// The minimal player the controller needs (just_audio in the app, a fake in tests).
abstract interface class AudioBackend {
  /// Loads [file]; returns its duration when known.
  Future<Duration?> setFile(File file);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Duration get position;

  /// Fires when the loaded file finishes playing.
  Stream<void> get completed;
}

const playbackSpeeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

enum PlayerStatus { idle, loading, playing, paused, finished }

@immutable
class PlayerState {
  const PlayerState({
    this.manifest,
    this.index = 0,
    this.status = PlayerStatus.idle,
    this.speed = 1.0,
    this.elapsed = Duration.zero,
    this.total = Duration.zero,
    this.round = 1,
    this.approximate = false,
    this.error,
  });

  final AudioManifest? manifest;
  final int index;
  final PlayerStatus status;
  final double speed;
  final Duration elapsed;
  final Duration total;

  /// Current pass when the manifest repeats (Repeat ×3).
  final int round;

  /// The current voice only approximates the language (Sanskrit via Hindi).
  final bool approximate;
  final String? error;

  AudioChunk? get chunk => manifest == null ? null : manifest!.chunks[index];
  Duration get remaining => total - elapsed > Duration.zero ? total - elapsed : Duration.zero;
  bool get isActive => manifest != null && status != PlayerStatus.idle;
}

/// Plays a manifest chunk by chunk:
///   synthesize/cache current chunk → play → on completion move to the next,
///   while the next two chunks are prepared in the background.
/// One global timeline spans all chunks (estimated durations are replaced by
/// real ones as files are loaded), so seek, ±15 s and remaining time work
/// across chunk boundaries. Progress is saved every 5 s and on pause.
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required this.backend,
    required this.synthesizer,
    required this.cache,
    required this.progress,
    DateTime Function()? clock,
    this.saveEvery = const Duration(seconds: 5),
    this.prefetch = 2,
  }) : _clock = clock ?? DateTime.now {
    _completedSub = backend.completed.listen((_) => _onChunkCompleted());
  }

  final AudioBackend backend;
  final AudioSynthesizer synthesizer;
  final AudioCache cache;
  final ListeningProgressRepository progress;
  final Duration saveEvery;
  final int prefetch;
  final DateTime Function() _clock;

  late final StreamSubscription<void> _completedSub;
  Timer? _ticker;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  int _generation = 0; // invalidates in-flight work when the user acts
  final Map<int, double> _durations = {};
  final Set<int> _prefetching = {};

  PlayerState _state = const PlayerState();
  PlayerState get state => _state;

  void _set(PlayerState s) {
    _state = s;
    notifyListeners();
  }

  PlayerState _copy({
    AudioManifest? manifest,
    int? index,
    PlayerStatus? status,
    double? speed,
    Duration? elapsed,
    int? round,
    bool? approximate,
    String? error,
    bool clearError = false,
  }) {
    final m = manifest ?? _state.manifest;
    return PlayerState(
      manifest: m,
      index: index ?? _state.index,
      status: status ?? _state.status,
      speed: speed ?? _state.speed,
      elapsed: elapsed ?? _state.elapsed,
      total: m == null ? Duration.zero : _secondsToDuration(_totalSeconds(m)),
      round: round ?? _state.round,
      approximate: approximate ?? _state.approximate,
      error: clearError ? null : (error ?? _state.error),
    );
  }

  // ---- timeline -------------------------------------------------------------

  double _durationOf(AudioManifest m, int i) => _durations[i] ?? m.chunks[i].estimatedSeconds;

  double _totalSeconds(AudioManifest m) {
    var t = 0.0;
    for (var i = 0; i < m.chunks.length; i++) {
      t += _durationOf(m, i);
    }
    return t;
  }

  double _startOf(AudioManifest m, int index) {
    var t = 0.0;
    for (var i = 0; i < index; i++) {
      t += _durationOf(m, i);
    }
    return t;
  }

  static Duration _secondsToDuration(double s) => Duration(milliseconds: (s * 1000).round());

  Duration _elapsedNow() {
    final m = _state.manifest;
    if (m == null) return Duration.zero;
    return _secondsToDuration(_startOf(m, _state.index) + backend.position.inMilliseconds / 1000);
  }

  // ---- loading --------------------------------------------------------------

  /// Starts [manifest]. With [resume], continues from the saved position.
  Future<void> open(AudioManifest manifest, {bool resume = true, bool autoplay = true}) async {
    final gen = ++_generation;
    if (_state.manifest != null && _state.manifest!.id != manifest.id) await save();
    _ticker?.cancel();
    await backend.stop();
    _durations.clear();
    _prefetching.clear();
    var index = 0;
    var offset = Duration.zero;
    var speed = _state.speed;
    if (resume && !manifest.ephemeral) {
      final saved = await progress.load(manifest.id);
      if (saved != null && !saved.completed) {
        final i = manifest.chunks.indexWhere((c) => c.id == saved.audioChunkId);
        if (i >= 0) {
          index = i;
          offset = _secondsToDuration(saved.positionSeconds);
        }
        speed = saved.speed;
      }
    }
    _set(PlayerState(manifest: manifest, index: index, status: PlayerStatus.loading, speed: speed));
    await backend.setSpeed(speed);
    await _prepare(gen, index, offset: offset, autoplay: autoplay);
  }

  Future<void> _prepare(
    int gen,
    int index, {
    Duration offset = Duration.zero,
    bool autoplay = true,
    int attempt = 1,
  }) async {
    final m = _state.manifest!;
    _set(_copy(index: index, status: PlayerStatus.loading, clearError: true));
    try {
      final r = await synthesizer.fileFor(m.chunks[index]);
      if (gen != _generation) return;
      final d = await backend.setFile(r.file);
      if (gen != _generation) return;
      if (d != null) {
        _durations[index] = d.inMilliseconds / 1000;
        unawaited(cache.setDuration(r.hash, _durations[index]!));
      }
      if (offset > Duration.zero) await backend.seek(offset);
      _set(_copy(approximate: r.choice.approximate, elapsed: _elapsedNow()));
      if (autoplay) {
        await _play();
      } else {
        _set(_copy(status: PlayerStatus.paused));
      }
      _prefetchFrom(index + 1);
    } on NoVoiceAvailable catch (e) {
      if (gen != _generation) return;
      _set(_copy(status: PlayerStatus.paused, error: 'no-voice:${e.language}'));
    } catch (e) {
      if (gen != _generation) return;
      // One retry, then skip the chunk so playback never stalls on one failure.
      if (attempt < 2) return _prepare(gen, index, offset: offset, autoplay: autoplay, attempt: attempt + 1);
      if (index + 1 < m.chunks.length) {
        _set(_copy(error: 'chunk-failed:${m.chunks[index].id}'));
        return _prepare(gen, index + 1, autoplay: autoplay);
      }
      _set(_copy(status: PlayerStatus.paused, error: 'chunk-failed:${m.chunks[index].id}'));
    }
  }

  void _prefetchFrom(int start) {
    final m = _state.manifest!;
    for (var i = start; i < start + prefetch && i < m.chunks.length; i++) {
      if (_prefetching.add(i)) {
        final gen = _generation;
        unawaited(
          synthesizer.fileFor(m.chunks[i]).then((r) {
            // A known length improves the timeline before the chunk plays.
            if (gen == _generation && r.seconds != null && !_durations.containsKey(i)) {
              _durations[i] = r.seconds!;
              _set(_copy());
            }
          }, onError: (_) => _prefetching.remove(i)),
        );
      }
    }
  }

  // ---- transport ------------------------------------------------------------

  Future<void> _play() async {
    _set(_copy(status: PlayerStatus.playing));
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    unawaited(backend.play());
  }

  void _tick() {
    if (_state.status != PlayerStatus.playing) return;
    _set(_copy(elapsed: _elapsedNow()));
    if (_clock().difference(_lastSave) >= saveEvery) unawaited(save());
  }

  Future<void> play() async {
    final m = _state.manifest;
    if (m == null) return;
    if (_state.status == PlayerStatus.finished) return open(m, resume: false);
    if (_state.status == PlayerStatus.paused) return _play();
  }

  Future<void> pause() async {
    if (_state.status != PlayerStatus.playing) return;
    _ticker?.cancel();
    await backend.pause();
    _set(_copy(status: PlayerStatus.paused, elapsed: _elapsedNow()));
    await save();
  }

  Future<void> togglePlay() => _state.status == PlayerStatus.playing ? pause() : play();

  Future<void> setSpeed(double speed) async {
    if (!playbackSpeeds.contains(speed)) throw ArgumentError.value(speed, 'speed');
    await backend.setSpeed(speed);
    _set(_copy(speed: speed));
    await save();
  }

  /// Seeks on the global timeline (across chunks).
  Future<void> seekTo(Duration target) async {
    final m = _state.manifest;
    if (m == null) return;
    final t = target.inMilliseconds / 1000;
    var start = 0.0;
    for (var i = 0; i < m.chunks.length; i++) {
      final d = _durationOf(m, i);
      if (t < start + d || i == m.chunks.length - 1) {
        final offset = _secondsToDuration((t - start).clamp(0, d));
        if (i == _state.index && _state.status != PlayerStatus.loading) {
          await backend.seek(offset);
          _set(_copy(elapsed: _elapsedNow()));
        } else {
          final wasPlaying = _state.status == PlayerStatus.playing;
          await backend.stop();
          await _prepare(++_generation, i, offset: offset, autoplay: wasPlaying);
        }
        await save();
        return;
      }
      start += d;
    }
  }

  Future<void> skip(Duration delta) {
    final next = _elapsedNow() + delta;
    return seekTo(next < Duration.zero ? Duration.zero : next);
  }

  /// Jumps to the first chunk of the next / previous verse.
  Future<void> nextVerse() => _jumpVerse(1);
  Future<void> previousVerse() => _jumpVerse(-1);

  Future<void> _jumpVerse(int dir) async {
    final m = _state.manifest;
    if (m == null) return;
    final current = m.chunks[_state.index].verseId;
    int target;
    if (dir > 0) {
      target = m.chunks.indexWhere((c) => c.verseId != current, _state.index);
      if (target < 0) return;
    } else {
      final firstOfCurrent = m.chunks.indexWhere((c) => c.verseId == current);
      // Like a music player: if well into this verse, restart it; else go back one verse.
      if (_elapsedNow().inMilliseconds / 1000 - _startOf(m, firstOfCurrent) > 3 || firstOfCurrent == 0) {
        target = firstOfCurrent;
      } else {
        final prevVerse = m.chunks[firstOfCurrent - 1].verseId;
        target = m.chunks.indexWhere((c) => c.verseId == prevVerse);
      }
    }
    final wasPlaying = _state.status == PlayerStatus.playing;
    await backend.stop();
    await _prepare(++_generation, target, autoplay: wasPlaying || _state.status == PlayerStatus.loading);
    await save();
  }

  Future<void> _onChunkCompleted() async {
    final m = _state.manifest;
    if (m == null || _state.status != PlayerStatus.playing) return;
    final gen = _generation;
    if (_state.index + 1 < m.chunks.length) {
      await _prepare(gen, _state.index + 1);
    } else if (_state.round < m.repeat) {
      _set(_copy(round: _state.round + 1));
      await _prepare(gen, 0);
    } else {
      _ticker?.cancel();
      _set(_copy(status: PlayerStatus.finished, elapsed: _state.total));
      await save(completed: true);
    }
  }

  Future<void> stop() async {
    _generation++;
    _ticker?.cancel();
    await save();
    await backend.stop();
    _set(const PlayerState());
  }

  /// Persists the current position (chapter, verse, chunk, seconds, speed).
  Future<void> save({bool completed = false}) async {
    final m = _state.manifest;
    final c = _state.chunk;
    if (m == null || c == null || m.ephemeral) return;
    _lastSave = _clock();
    await progress.save(
      ListeningPosition(
        manifestId: m.id,
        chapter: m.chapter,
        verseId: c.verseId,
        audioChunkId: c.id,
        positionSeconds: completed ? 0 : backend.position.inMilliseconds / 1000,
        speed: _state.speed,
        completed: completed,
        updatedAt: _clock(),
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_completedSub.cancel());
    super.dispose();
  }
}
