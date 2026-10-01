import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/app/app.dart';
import 'package:gita_companion/app/providers.dart';
import 'package:gita_companion/core/audio/tts_provider.dart';
import 'package:gita_companion/core/content/sqlite_content_repository.dart';
import 'package:gita_companion/core/search/search_service.dart';
import 'package:gita_companion/core/settings/app_settings.dart';
import 'package:go_router/go_router.dart';

import 'support/audio_fakes.dart';
import 'support/pack.dart';
import 'widgets_test.dart' show MemorySettingsRepository;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late SqliteContentRepository content;
  late SqliteSearchService search;
  setUpAll(() {
    final db = openPackWithSampleAi();
    content = SqliteContentRepository(db);
    search = SqliteSearchService(db, verseExists: content.readingOrder().toSet().contains);
  });

  Future<({TestAudio audio, MemorySettingsRepository store})> pumpAt(
    WidgetTester tester,
    String route, {
    TestAudio? audio,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final a = audio ?? TestAudio();
    const s = AppSettings(onboardingDone: true);
    final store = MemorySettingsRepository()..saved = s;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentRepositoryProvider.overrideWithValue(content),
          searchServiceProvider.overrideWithValue(search),
          settingsRepositoryProvider.overrideWithValue(store),
          initialSettingsProvider.overrideWithValue(s),
          clockProvider.overrideWithValue(() => DateTime(2026, 10, 1)),
          ...a.overrides,
        ],
        child: const GitaApp(),
      ),
    );
    await tester.pumpAndSettle();
    GoRouterHelper(tester.element(find.byType(Scaffold).first)).go(route);
    await tester.pumpAndSettle();
    return (audio: a, store: store);
  }

  // Real async work (database, files) runs outside the fake clock.
  Future<void> work(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Recite opens the player; Sanskrit via Hindi voice is labelled approximate', (tester) async {
    final r = await pumpAt(tester, '/verse/2.47');
    await tester.tap(find.text('Recite'));
    await work(tester);
    await tester.pumpAndSettle();

    expect(find.text('Now playing'), findsOneWidget);
    expect(find.textContaining('कर्मण्येवाधिकारस्ते'), findsWidgets);
    expect(find.textContaining('pronunciation is approximate'), findsOneWidget);
    expect(r.audio.tts.calls.first.voice.id, 'hi-voice');
    expect(r.audio.backend.playing, isTrue);
  });

  testWidgets('the mini player appears on other screens and can stop playback', (tester) async {
    final r = await pumpAt(tester, '/verse/2.47');
    await tester.tap(find.text('Recite'));
    await work(tester);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Stop and close'), findsOneWidget, reason: 'mini player is shown');
    await tester.tap(find.bySemanticsLabel('Stop and close'));
    await work(tester);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Stop and close'), findsNothing);
    expect(r.audio.backend.playing, isFalse);
  });

  testWidgets('Start listening on a chapter plays every verse in order', (tester) async {
    final r = await pumpAt(tester, '/chapters/12');
    await tester.tap(find.text('Start listening'));
    await work(tester);
    await tester.pumpAndSettle();
    expect(find.text('Verse 12.1'), findsOneWidget);
    expect(find.text('Chapter 12 · Recitation'), findsOneWidget);
    // Recitation chunks are synthesized ahead of playback.
    expect(r.audio.tts.calls.length, greaterThanOrEqualTo(2));
  });

  testWidgets('pausing records progress, shown as Continue listening on Home', (tester) async {
    await pumpAt(tester, '/chapters/12');
    await tester.tap(find.text('Start listening'));
    await work(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pause'));
    await work(tester);
    await tester.pumpAndSettle();

    GoRouterHelper(tester.element(find.byType(Scaffold).first)).go('/');
    await work(tester);
    await tester.pumpAndSettle();
    expect(find.text('CONTINUE LISTENING'), findsOneWidget);
    expect(find.textContaining('Listening progress: 0%'), findsOneWidget);
    expect(find.text('Chapter 12 · Verse 12.1'), findsOneWidget);
  });

  testWidgets('speed chips change the playback speed', (tester) async {
    final r = await pumpAt(tester, '/verse/2.47');
    await tester.tap(find.text('Recite'));
    await work(tester);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('1.5x'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('1.5x'));
    await work(tester);
    await tester.pumpAndSettle();
    expect(r.audio.backend.speed, 1.5);
  });

  testWidgets('voice choice is saved in settings', (tester) async {
    final audio = TestAudio(
      tts: FakeTtsProvider(
        voices: const [
          Voice(id: 'en-a', name: 'Asha', locale: 'en-IN'),
          Voice(id: 'en-b', name: 'Bala', locale: 'en-IN'),
          Voice(id: 'te-a', name: 'Teja', locale: 'te-IN'),
          Voice(id: 'hi-a', name: 'Hema', locale: 'hi-IN'),
        ],
      ),
    );
    final r = await pumpAt(tester, '/settings', audio: audio);
    await tester.scrollUntilVisible(
      find.text('English voice'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await work(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Automatic').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bala (en-IN)').last);
    await tester.pumpAndSettle();
    expect(r.store.saved.voicePrefs, {'en': 'en-b'});
  });

  testWidgets('a missing Telugu voice shows how to install one', (tester) async {
    final audio = TestAudio(
      tts: FakeTtsProvider(
        voices: const [Voice(id: 'en', name: 'E', locale: 'en-IN')],
      ),
    );
    await pumpAt(tester, '/settings', audio: audio);
    await tester.scrollUntilVisible(
      find.text('Telugu voice'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await work(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('No Telugu voice is installed'), findsOneWidget);
  });
}
