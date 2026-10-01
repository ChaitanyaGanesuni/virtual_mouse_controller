import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/audio_cache.dart';
import '../core/audio/listening_progress.dart';
import '../core/audio/manifest_resolver.dart';
import '../core/audio/playback_controller.dart';
import '../core/audio/synthesizer.dart';
import '../core/audio/tts_provider.dart';
import '../core/content/content_repository.dart';
import '../core/search/search_service.dart';
import '../core/settings/app_settings.dart';

/// Composition root. Real implementations are supplied in main.dart via
/// ProviderScope overrides; tests supply fakes the same way.
final contentRepositoryProvider = Provider<ContentRepository>(
  (ref) => throw UnimplementedError('contentRepositoryProvider must be overridden'),
);

final searchServiceProvider = Provider<SearchService>(
  (ref) => throw UnimplementedError('searchServiceProvider must be overridden'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => throw UnimplementedError('settingsRepositoryProvider must be overridden'),
);

/// Settings loaded at startup, before the first frame.
final initialSettingsProvider = Provider<AppSettings>((ref) => const AppSettings());

/// Clock, overridable in tests (Today's verse depends on the date).
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  Future<void> update(AppSettings Function(AppSettings) change) async {
    final next = change(state);
    if (next == state) return;
    state = next;
    await ref.read(settingsRepositoryProvider).save(next);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

// ---- audio ----------------------------------------------------------------
// The audio stack is assembled from small providers so tests can replace
// any part (TTS engines, player backend, storage) with fakes.

/// TTS engines in cost order (device first). Overridden in main.dart.
final ttsProvidersProvider = Provider<List<TtsProvider>>((ref) => const []);

final audioBackendProvider = Provider<AudioBackend>(
  (ref) => throw UnimplementedError('audioBackendProvider must be overridden'),
);

final audioCacheProvider = Provider<AudioCache>(
  (ref) => throw UnimplementedError('audioCacheProvider must be overridden'),
);

final listeningProgressProvider = Provider<ListeningProgressRepository>(
  (ref) => throw UnimplementedError('listeningProgressProvider must be overridden'),
);

final synthesizerProvider = Provider<AudioSynthesizer>(
  (ref) => AudioSynthesizer(
    providers: ref.watch(ttsProvidersProvider),
    cache: ref.watch(audioCacheProvider),
    voicePrefs: () => ref.read(settingsProvider).voicePrefs,
  ),
);

final playbackControllerProvider = Provider<PlaybackController>((ref) {
  final controller = PlaybackController(
    backend: ref.watch(audioBackendProvider),
    synthesizer: ref.watch(synthesizerProvider),
    cache: ref.watch(audioCacheProvider),
    progress: ref.watch(listeningProgressProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final manifestResolverProvider = Provider<ManifestResolver>(
  (ref) => ManifestResolver(ref.watch(contentRepositoryProvider)),
);
