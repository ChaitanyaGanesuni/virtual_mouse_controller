import 'dart:async';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';

import 'tts_provider.dart';

/// The platform's own TTS (Android TextToSpeech, iOS AVSpeechSynthesizer).
/// Free, offline once voices are installed, and first in the cost hierarchy.
class DeviceTtsProvider implements TtsProvider {
  DeviceTtsProvider([FlutterTts? tts]) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _initialised = false;

  // Serialise synthesis: the platform engine handles one request at a time.
  Future<void> _queue = Future.value();

  @override
  String get id => 'device';

  @override
  String get version => '1';

  @override
  TtsCapabilities get capabilities =>
      const TtsCapabilities(local: true, streaming: false, maxChars: 3900, nativeSanskrit: false);

  Future<void> _init() async {
    if (_initialised) return;
    await _tts.awaitSynthCompletion(true);
    _initialised = true;
  }

  @override
  Future<List<Voice>> getVoices() async {
    final raw = await _tts.getVoices;
    if (raw is! List) return const [];
    final voices = <Voice>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final name = item['name']?.toString();
      final locale = item['locale']?.toString();
      if (name == null || locale == null) continue;
      final network = item['network_required']?.toString() == '1' || name.contains('network');
      voices.add(Voice(id: name, name: name, locale: locale.replaceAll('_', '-'), requiresNetwork: network));
    }
    return voices;
  }

  @override
  Future<Set<String>> getSupportedLanguages() async => {for (final v in await getVoices()) v.language};

  @override
  Future<void> synthesizeToFile(SynthesisRequest request, File out) {
    final job = _queue.then((_) => _synthesize(request, out));
    _queue = job.catchError((_) {});
    return job;
  }

  Future<void> _synthesize(SynthesisRequest request, File out) async {
    await _init();
    await _tts.setVoice({'name': request.voice.id, 'locale': request.voice.locale});
    // flutter_tts doubles this on Android: 0.5 is the engine's normal rate.
    await _tts.setSpeechRate(0.5 * request.rate);
    final result = await _tts.synthesizeToFile(request.text, out.path, true);
    // The plugin reports 1 on success and 0 on failure.
    if (result == 0 || result == false) {
      throw TtsException('device TTS failed (result $result)');
    }
  }
}
