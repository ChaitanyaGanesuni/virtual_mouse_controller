import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/api/api_client.dart';
import '../core/api/server_address.dart';
import '../core/api/token_store.dart';

import '../core/audio/audio_cache.dart';
import '../core/audio/listening_progress.dart';
import '../core/audio/manifest_resolver.dart';
import '../core/audio/playback_controller.dart';
import '../core/audio/synthesizer.dart';
import '../core/audio/tts_provider.dart';
import '../core/content/content_pack.dart';
import '../core/content/content_repository.dart';
import '../core/packs/content_updates.dart';
import '../core/packs/download_manager.dart';
import '../core/packs/downloader.dart';
import '../core/packs/offline_audio.dart';
import '../core/packs/pack_catalog.dart';
import '../core/db/user_database.dart';
import '../core/study/auto_sync.dart';
import '../core/study/study_repository.dart';
import '../core/study/sync_service.dart';
import '../core/search/search_service.dart';
import '../core/settings/app_settings.dart';
import '../features/tutor/tutor_api.dart';

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

// ---- AI teacher (the only part of the app that needs the network) ---------

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Overridden in main.dart with the Keystore-backed store.
final tokenStoreProvider = Provider<TokenStore>((ref) => MemoryTokenStore());

/// The address compiled into the app (overridable in tests).
final builtInServerAddressProvider = Provider<String>((ref) => builtInServerAddress);

/// The server in use: the user's choice in Settings, else the built-in one.
final serverAddressProvider = Provider<String>(
  (ref) => effectiveServerAddress(
    ref.watch(settingsProvider).tutorServer,
    builtIn: ref.watch(builtInServerAddressProvider),
  ),
);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    client: ref.watch(httpClientProvider),
    serverAddress: () => ref.read(serverAddressProvider),
    tokens: ref.watch(tokenStoreProvider),
  ),
);

final tutorApiProvider = Provider<TutorApi>((ref) => TutorApi(ref.watch(apiClientProvider)));

// ---- My Gita: study data and sync ------------------------------------------

/// The user's database. main.dart supplies the on-disk one; tests get a
/// fresh in-memory database.
final userDatabaseProvider = Provider<UserDatabase>((ref) {
  final db = UserDatabase.memory();
  ref.onDispose(db.close);
  return db;
});

final studyRepositoryProvider = Provider<StudyRepository>(
  (ref) => StudyRepository(ref.watch(userDatabaseProvider), clock: ref.watch(clockProvider)),
);

final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(
    ref.watch(userDatabaseProvider),
    ref.watch(apiClientProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Started by the app; keeps data in step while sync is on.
final autoSyncProvider = Provider<AutoSync>((ref) {
  final auto = AutoSync(ref.watch(userDatabaseProvider), ref.watch(syncServiceProvider))..start();
  ref.onDispose(auto.dispose);
  return auto;
});

final verseStudyProvider = StreamProvider.family<VerseStudy, String>(
  (ref, verseId) => ref.watch(studyRepositoryProvider).watchVerse(verseId),
);

final studyProgressProvider = StreamProvider<StudyProgress>(
  (ref) => ref.watch(studyRepositoryProvider).watchProgress(),
);

final dueCountProvider = StreamProvider<int>((ref) => ref.watch(studyRepositoryProvider).watchDueCount());

final continueReadingProvider = StreamProvider<String?>(
  (ref) => ref.watch(studyRepositoryProvider).watchContinue(),
);

final syncStatusProvider = StreamProvider<SyncStatus>((ref) => ref.watch(syncServiceProvider).watchStatus());

// ---- Offline downloads ----------------------------------------------------

/// Where content packs are installed; null where content updates are not
/// possible (tests). Overridden in main.dart.
final contentDirectoryProvider = Provider<Directory?>((ref) => null);

/// The content pack the app opened at startup. Overridden in main.dart.
final installedContentProvider = Provider<InstalledContent?>((ref) => null);

final packCatalogClientProvider = Provider<PackCatalogClient>(
  (ref) => PackCatalogClient(ref.watch(httpClientProvider), () => ref.read(serverAddressProvider)),
);

final offlineAudioProvider = Provider<OfflineAudio>((ref) {
  final cache = ref.watch(audioCacheProvider);
  return OfflineAudio(
    db: cache.db,
    cache: cache,
    synthesizer: ref.watch(synthesizerProvider),
    resolver: ref.watch(manifestResolverProvider),
  );
});

final downloadManagerProvider = Provider<DownloadManager>((ref) {
  final dir = ref.watch(contentDirectoryProvider);
  final installed = ref.watch(installedContentProvider);
  final manager = DownloadManager(
    db: ref.watch(audioCacheProvider).db,
    catalogClient: ref.watch(packCatalogClientProvider),
    offlineAudio: ref.watch(offlineAudioProvider),
    contentUpdates: dir == null || installed == null
        ? null
        : ContentUpdates(
            directory: dir,
            downloader: Downloader(ref.watch(httpClientProvider)),
            installed: installed,
          ),
    clock: ref.watch(clockProvider),
  );
  manager.init();
  ref.onDispose(manager.dispose);
  return manager;
});

/// Downloads screen data for an audio language.
final downloadsOverviewProvider = StreamProvider.family<DownloadsOverview, String>(
  (ref, language) => ref.watch(downloadManagerProvider).watch(language),
);
