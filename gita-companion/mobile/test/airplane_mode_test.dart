import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/app/app.dart';
import 'package:gita_companion/app/providers.dart';
import 'package:gita_companion/core/audio/audio_cache.dart';
import 'package:gita_companion/core/audio/listening_progress.dart';
import 'package:gita_companion/core/audio/tts_provider.dart';
import 'package:gita_companion/core/content/content_pack.dart';
import 'package:gita_companion/core/content/sqlite_content_repository.dart';
import 'package:gita_companion/core/db/user_database.dart';
import 'package:gita_companion/core/search/search_service.dart';
import 'package:gita_companion/core/settings/app_settings.dart';
import 'package:gita_companion/core/study/study_repository.dart';
import 'package:go_router/go_router.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

import 'support/audio_fakes.dart';
import 'support/fake_pack_server.dart';
import 'support/finders.dart';
import 'support/pack.dart';
import 'widgets_test.dart' show MemorySettingsRepository;

/// Device speech that stops working (to prove offline audio is played from
/// the downloaded files, never synthesized again).
class SwitchableTts extends FakeTtsProvider {
  bool broken = false;

  @override
  Future<void> synthesizeToFile(SynthesisRequest request, File out) async {
    if (broken) throw TtsException('no speech engine in this test phase');
    return super.synthesizeToFile(request, out);
  }
}

/// Phase 9 exit criterion: with everything downloaded while online, the
/// phone goes into airplane mode, the app is restarted, and every
/// downloaded feature still works: the updated content, chapter audio,
/// search, the reader, My Gita. Network-only features say so politely.
void main() {
  testWidgets('airplane mode: every downloaded feature works', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    final root = Directory.systemTemp.createTempSync('airplane');
    final contentDir = Directory('${root.path}/content');
    final audioDir = Directory('${root.path}/audio');
    final userDbFile = File('${root.path}/user.sqlite');
    final server = FakePackServer(makeUpdatedPack());
    final tts = SwitchableTts();
    const settings = AppSettings(onboardingDone: true);

    // One app "start": install content, open the user database, build the app.
    Future<(UserDatabase, FakeBackend, InstalledContent)> start() async {
      final installed = await tester.runAsync(() async {
        final installer = ContentPackInstaller(directory: contentDir, loadAsset: loadAssetFromDisk);
        final Database db = await installer.install();
        return (db, installer.active!);
      });
      final (contentDb, active) = installed!;
      final content = SqliteContentRepository(contentDb);
      final userDb = UserDatabase(NativeDatabase(userDbFile));
      final backend = FakeBackend();
      final overrides = <Override>[
        contentRepositoryProvider.overrideWithValue(content),
        searchServiceProvider.overrideWithValue(
          SqliteSearchService(contentDb, verseExists: content.readingOrder().toSet().contains),
        ),
        settingsRepositoryProvider.overrideWithValue(MemorySettingsRepository()..saved = settings),
        initialSettingsProvider.overrideWithValue(settings),
        userDatabaseProvider.overrideWithValue(userDb),
        contentDirectoryProvider.overrideWithValue(contentDir),
        installedContentProvider.overrideWithValue(active),
        httpClientProvider.overrideWithValue(server.client),
        builtInServerAddressProvider.overrideWithValue(packServer),
        ttsProvidersProvider.overrideWithValue([tts]),
        audioBackendProvider.overrideWithValue(backend),
        audioCacheProvider.overrideWithValue(AudioCache(directory: audioDir, db: userDb)),
        listeningProgressProvider.overrideWithValue(ListeningProgressRepository(userDb)),
      ];
      await tester.pumpWidget(ProviderScope(overrides: overrides, child: const GitaApp()));
      await tester.pumpAndSettle();
      return (userDb, backend, active);
    }

    void go(String route) => GoRouterHelper(tester.element(find.byType(Scaffold).first)).go(route);

    Future<void> work() async {
      // Not pumpAndSettle: progress indicators animate until data arrives.
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // Downloads started by a tap run in the test's zone: pump until done.
    Future<void> idle() async {
      final manager = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
          .read(downloadManagerProvider);
      for (var i = 0; i < 600 && manager.busy; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(manager.busy, isFalse, reason: 'downloads finished');
    }

    // ---- Online: download the content update and chapter 12's audio. ----
    var (userDb, backend, active) = await start();
    expect(active.downloaded, isFalse);
    await tester.runAsync(() => StudyRepository(userDb).setBookmarked('12.13', true));
    go('/settings/downloads');
    await work();
    expect(find.textContaining('New texts and explanations are available'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Download'));
    await idle();
    await work();
    expect(find.text('Downloaded. Used the next time the app starts.'), findsOneWidget);

    final chapter12 = find.ancestor(of: find.textContaining('Chapter 12 ·'), matching: find.byType(ListTile));
    await tester.scrollUntilVisible(chapter12, 300, scrollable: mainList());
    await tester.tap(find.descendant(of: chapter12, matching: find.byTooltip('Download')));
    await idle();
    await work();
    expect(
      find.descendant(of: chapter12, matching: find.textContaining('Available offline')),
      findsOneWidget,
    );
    final synthesized = tts.calls.length;
    expect(synthesized, greaterThan(20));

    // ---- Airplane mode, and the app is restarted. ----
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(userDb.close);
    server.offline = true;
    tts.broken = true;
    (userDb, backend, active) = await start();
    expect(active.downloaded, isTrue, reason: 'the downloaded content update is in use');

    // The updated content, in the reader.
    go('/verse/12.13');
    await work();
    final updated = find.textContaining('UPDATED TRANSLATION', findRichText: true);
    await tester.scrollUntilVisible(updated, 200, scrollable: mainList());
    expect(updated, findsWidgets);

    // Chapter audio plays from the downloaded files; nothing is synthesized.
    go('/chapters/12');
    await work();
    expect(find.byTooltip('Available offline'), findsOneWidget);
    await tester.tap(find.text('Start listening'));
    await work();
    expect(backend.playing, isTrue);
    expect(backend.loaded, isNotEmpty);
    expect(tts.calls.length, synthesized, reason: 'no new synthesis in airplane mode');

    // Search and My Gita work.
    go('/search');
    await work();
    await tester.enterText(find.byType(TextField), 'How do I control my anger?');
    await work();
    expect(find.text('Anger (krodha)'), findsOneWidget);
    go('/my');
    await work();
    await tester.tap(find.text('Saved'));
    await work();
    expect(find.text('Verse 12.13'), findsOneWidget);

    // Downloads: honest about what cannot be checked; downloads still there.
    go('/settings/downloads');
    await work();
    expect(find.textContaining('No connection: cannot check for updates'), findsOneWidget);
    await tester.scrollUntilVisible(chapter12, 300, scrollable: mainList());
    expect(
      find.descendant(of: chapter12, matching: find.textContaining('Available offline')),
      findsOneWidget,
    );

    // The AI teacher needs the internet and says so.
    go('/tutor');
    await work();
    await tester.enterText(find.byType(TextField), 'Explain 2.47');
    await tester.tap(find.byTooltip('Send'));
    await work();
    expect(find.textContaining("You're offline"), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(userDb.close);
  });
}
