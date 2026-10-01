import 'package:audio_service/audio_service.dart';

import 'playback_controller.dart';

/// Connects the [PlaybackController] to the system: background playback,
/// the media notification, lock screen and Bluetooth/headset buttons.
/// "Skip to next/previous" move by verse; fast-forward/rewind by 15 s.
class GitaAudioHandler extends BaseAudioHandler with SeekHandler {
  GitaAudioHandler(this.controller) {
    controller.addListener(_publish);
  }

  final PlaybackController controller;

  static const skipInterval = Duration(seconds: 15);

  void _publish() {
    final s = controller.state;
    final chunk = s.chunk;
    if (s.manifest != null && chunk != null) {
      final verse = chunk.verseId;
      mediaItem.add(
        MediaItem(
          id: s.manifest!.id,
          title: verse == null ? 'Bhagavad Gita' : 'Bhagavad Gita $verse',
          album: s.manifest!.chapter == null ? 'Bhagavad Gita' : 'Chapter ${s.manifest!.chapter}',
          artist: chunk.section == 'recitation' ? 'Recitation' : 'Explanation',
          duration: s.total,
        ),
      );
    }
    final playing = s.status == PlayerStatus.playing;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.rewind,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.fastForward,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
        androidCompactActionIndices: const [0, 2, 4],
        processingState: switch (s.status) {
          PlayerStatus.idle => AudioProcessingState.idle,
          PlayerStatus.loading => AudioProcessingState.loading,
          PlayerStatus.finished => AudioProcessingState.completed,
          _ => AudioProcessingState.ready,
        },
        playing: playing,
        updatePosition: s.elapsed,
        speed: s.speed,
      ),
    );
  }

  @override
  Future<void> play() => controller.play();

  @override
  Future<void> pause() => controller.pause();

  @override
  Future<void> stop() async {
    await controller.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => controller.seekTo(position);

  @override
  Future<void> fastForward() => controller.skip(skipInterval);

  @override
  Future<void> rewind() => controller.skip(-skipInterval);

  @override
  Future<void> skipToNext() => controller.nextVerse();

  @override
  Future<void> skipToPrevious() => controller.previousVerse();

  @override
  Future<void> setSpeed(double speed) =>
      playbackSpeeds.contains(speed) ? controller.setSpeed(speed) : Future.value();
}
