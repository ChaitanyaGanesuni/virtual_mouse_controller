import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/providers.dart';
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

  // Everything the app needs is on the device: no network at startup.
  final support = await getApplicationSupportDirectory();
  final contentDb = await ContentPackInstaller(
    directory: Directory(p.join(support.path, 'content')),
    loadAsset: rootBundle.load,
  ).install();
  final userDb = UserDatabase.inDirectory(support);
  final settingsRepo = DriftSettingsRepository(userDb);
  final settings = await settingsRepo.load();
  final content = SqliteContentRepository(contentDb);
  final verseIds = content.readingOrder().toSet();

  runApp(
    ProviderScope(
      overrides: [
        contentRepositoryProvider.overrideWithValue(content),
        searchServiceProvider.overrideWithValue(
          SqliteSearchService(contentDb, verseExists: verseIds.contains),
        ),
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        initialSettingsProvider.overrideWithValue(settings),
      ],
      child: const GitaApp(),
    ),
  );
}
