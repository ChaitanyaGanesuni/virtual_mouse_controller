import 'dart:io';

import 'package:flutter/services.dart';

/// Shrinks synthesized speech before it is cached. Device TTS writes
/// uncompressed WAV (~44 kB per second); AAC at 40 kbit/s is ~5 kB per
/// second and sounds the same for speech, so a chapter downloaded for
/// offline listening takes about a ninth of the space.
abstract interface class AudioCompressor {
  /// Bytes per second of compressed speech, for size estimates.
  int get bytesPerSecond;

  /// Writes a compressed copy of [wav] next to it and returns it, or null
  /// if compression is not possible (the WAV is then kept as it is).
  Future<File?> compress(File wav);
}

/// Android's built-in AAC encoder (MediaCodec), via MainActivity.kt.
class PlatformAacCompressor implements AudioCompressor {
  PlatformAacCompressor({this.bitrate = 40000});

  static const _channel = MethodChannel('app.gitacompanion/audio_codec');
  final int bitrate;

  @override
  int get bytesPerSecond => bitrate ~/ 8;

  @override
  Future<File?> compress(File wav) async {
    final out = File(wav.path.replaceFirst(RegExp(r'\.wav(\.part)?$'), '.m4a'));
    try {
      await _channel.invokeMethod<void>('wavToM4a', {
        'input': wav.path,
        'output': out.path,
        'bitrate': bitrate,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
    return out.existsSync() && out.lengthSync() > 0 ? out : null;
  }
}
