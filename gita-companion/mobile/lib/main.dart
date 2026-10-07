import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:audio_service/audio_service.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/audio/audio_cache.dart';
import 'core/audio/audio_handler.dart';
import 'core/audio/device_tts_provider.dart';
import 'core/audio/just_audio_backend.dart';
import 'core/api/token_store.dart';
import 'core/audio/listening_progress.dart';
import 'core/content/content_pack.dart';
import 'core/content/sqlite_content_repository.dart';
import 'core/db/user_database.dart';
import 'core/search/search_service.dart';
import 'core/settings/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final ofl = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['Noto Serif', 'Noto Serif Devanagari', 'Noto Sans Telugu'], ofl);
  });

  // Everything except the AI teacher is on the device: no network at startup.
  final support = await getApplicationSupportDirectory();
  final contentDir = Directory(p.join(support.path, 'content'));
  final installer = ContentPackInstaller(directory: contentDir, loadAsset: rootBundle.load);
  final contentDb = await installer.install();
  final userDb = UserDatabase.inDirectory(support);
  final settingsRepo = DriftSettingsRepository(userDb);
  final settings = await settingsRepo.load();
  final content = SqliteContentRepository(contentDb);
  final verseIds = content.readingOrder().toSet();

  final container = ProviderContainer(
    overrides: [
      contentRepositoryProvider.overrideWithValue(content),
      searchServiceProvider.overrideWithValue(SqliteSearchService(contentDb, verseExists: verseIds.contains)),
      settingsRepositoryProvider.overrideWithValue(settingsRepo),
      userDatabaseProvider.overrideWithValue(userDb),
      // Content updates are downloaded next to the installed pack.
      contentDirectoryProvider.overrideWithValue(contentDir),
      installedContentProvider.overrideWithValue(installer.active),
      initialSettingsProvider.overrideWithValue(settings),
      // Audio: device TTS first (free, offline); more engines plug in here.
      ttsProvidersProvider.overrideWithValue([DeviceTtsProvider()]),
      audioBackendProvider.overrideWithValue(JustAudioBackend()),
      audioCacheProvider.overrideWithValue(
        AudioCache(directory: Directory(p.join(support.path, 'audio')), db: userDb),
      ),
      listeningProgressProvider.overrideWithValue(ListeningProgressRepository(userDb)),
      // AI teacher credentials live in the Android Keystore.
      tokenStoreProvider.overrideWithValue(SecureTokenStore()),
    ],
  );

  // Background playback, notification and lock-screen controls.
  try {
    await AudioService.init(
      builder: () => GitaAudioHandler(container.read(playbackControllerProvider)),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'app.gitacompanion.audio',
        androidNotificationChannelName: 'Gita Companion audio',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (e) {
    // Playback still works in the foreground without the service.
    debugPrint('AudioService unavailable: $e');
  }

  runApp(UncontrolledProviderScope(container: container, child: const GitaApp()));
}
