import 'dart:io';

import 'audio_cache.dart';
import 'compressor.dart';
import 'manifest.dart';
import 'tts_provider.dart';
import 'wav.dart';

/// Which provider and voice will speak a chunk, and whether the result is
/// only an approximation (Sanskrit read by a Hindi voice).
class VoiceChoice {
  const VoiceChoice({required this.provider, required this.voice, required this.approximate});

  final TtsProvider provider;
  final Voice voice;
  final bool approximate;
}

class NoVoiceAvailable implements Exception {
  NoVoiceAvailable(this.language);

  final String language;

  @override
  String toString() => 'No voice is installed for "$language"';
}

/// Turns chunks into audio files: picks a provider and voice (user
/// preference first, then the cost hierarchy: providers are tried in the
/// order given, which is cheapest/most local first), and serves from the
/// content-addressed cache before synthesizing anything.
class AudioSynthesizer {
  AudioSynthesizer({required this.providers, required this.cache, required this.voicePrefs, this.compressor});

  /// Shrinks WAV before caching (null: keep WAV).
  final AudioCompressor? compressor;

  /// In priority order (device → on-device neural → server …).
  final List<TtsProvider> providers;
  final AudioCache cache;

  /// language ('en', 'te', 'sa') → preferred voice id.
  final Map<String, String> Function() voicePrefs;

  final Map<String, List<Voice>> _voices = {};

  Future<List<Voice>> _voicesOf(TtsProvider p) async => _voices[p.id] ??= await p.getVoices();

  /// Sanskrit has no voice on most devices; Hindi reads Devanagari closely
  /// enough to be useful, and is labelled "approximate" in the UI.
  static const _fallbackLanguages = {
    'sa': ['sa', 'hi'],
  };

  Future<VoiceChoice> choose(AudioChunk chunk) async {
    final wanted = voicePrefs()[chunk.language];
    final languages = _fallbackLanguages[chunk.language] ?? [chunk.language];
    // A preferred voice wins if any provider still has it.
    if (wanted != null) {
      for (final p in providers) {
        final v = (await _voicesOf(p)).where((v) => v.id == wanted).firstOrNull;
        if (v != null) {
          return VoiceChoice(
            provider: p,
            voice: v,
            approximate: chunk.language == 'sa' && v.language != 'sa',
          );
        }
      }
    }
    for (final lang in languages) {
      for (final p in providers) {
        final candidates = (await _voicesOf(p)).where((v) => v.language == lang).toList()
          ..sort((a, b) => _rank(a).compareTo(_rank(b)));
        if (candidates.isNotEmpty) {
          return VoiceChoice(provider: p, voice: candidates.first, approximate: lang != chunk.language);
        }
      }
    }
    throw NoVoiceAvailable(chunk.language);
  }

  // Prefer offline voices and Indian locales (en-IN reads Sanskrit names better).
  static int _rank(Voice v) => (v.requiresNetwork ? 10 : 0) + (v.locale.toUpperCase().endsWith('IN') ? 0 : 1);

  String hashFor(AudioChunk chunk, VoiceChoice c) => audioHash(
    text: chunk.text,
    language: chunk.language,
    provider: c.provider.id,
    providerVersion: c.provider.version,
    voice: c.voice.id,
    rate: chunk.rate,
  );

  /// Returns the audio file for [chunk], synthesizing it only on a cache miss.
  Future<({File file, String hash, VoiceChoice choice, double? seconds})> fileFor(AudioChunk chunk) async {
    final choice = await choose(chunk);
    final hash = hashFor(chunk, choice);
    final cached = await cache.get(hash);
    if (cached != null) {
      return (file: cached, hash: hash, choice: choice, seconds: await cache.duration(hash));
    }

    await cache.directory.create(recursive: true);
    final out = cache.fileFor(hash);
    final tmp = File('${out.path}.part');
    await choice.provider.synthesizeToFile(
      SynthesisRequest(text: chunk.text, language: chunk.language, voice: choice.voice, rate: chunk.rate),
      tmp,
    );
    if (!tmp.existsSync() || tmp.lengthSync() == 0) {
      throw TtsException('${choice.provider.id} produced no audio for ${chunk.id}');
    }
    await tmp.rename(out.path);
    final seconds = wavDurationSeconds(out);
    var file = out;
    final compressed = await compressor?.compress(out);
    if (compressed != null) {
      await out.delete();
      file = compressed;
    }
    await cache.put(
      hash,
      file,
      provider: choice.provider.id,
      voice: choice.voice.id,
      durationSeconds: seconds,
    );
    return (file: file, hash: hash, choice: choice, seconds: seconds);
  }
}
