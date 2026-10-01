import 'dart:io';

/// A voice offered by a provider.
class Voice {
  const Voice({required this.id, required this.name, required this.locale, this.requiresNetwork = false});

  final String id;
  final String name;

  /// BCP-47, e.g. 'en-IN', 'te-IN', 'hi-IN'.
  final String locale;
  final bool requiresNetwork;

  String get language => locale.split(RegExp('[-_]')).first.toLowerCase();

  @override
  bool operator ==(Object other) => other is Voice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class TtsCapabilities {
  const TtsCapabilities({
    required this.local,
    required this.streaming,
    required this.maxChars,
    required this.nativeSanskrit,
  });

  /// Runs on the device without network.
  final bool local;
  final bool streaming;

  /// Longest text accepted in one request.
  final int maxChars;

  /// Has a real Sanskrit voice (not an approximation through Hindi).
  final bool nativeSanskrit;
}

class SynthesisRequest {
  const SynthesisRequest({required this.text, required this.language, required this.voice, this.rate = 1.0});

  final String text;
  final String language;
  final Voice voice;

  /// Synthesis-level rate (1.0 normal; 0.7 slow recitation).
  final double rate;
}

class TtsException implements Exception {
  TtsException(this.message);

  final String message;

  @override
  String toString() => 'TtsException: $message';
}

/// Every TTS engine (device, on-device neural, server, recordings) produces
/// an audio file, so the cache and player are the same for all of them.
/// Adding a provider means implementing this interface and registering it;
/// nothing else in the app changes.
abstract interface class TtsProvider {
  String get id;

  /// Part of the cache key: a new engine/voice version never reuses old audio.
  String get version;

  TtsCapabilities get capabilities;

  Future<List<Voice>> getVoices();

  Future<Set<String>> getSupportedLanguages();

  /// Writes audio for [request] to [out] (any format the player can read).
  Future<void> synthesizeToFile(SynthesisRequest request, File out);
}
