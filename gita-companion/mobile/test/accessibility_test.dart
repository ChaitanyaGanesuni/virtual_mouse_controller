import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/app/app.dart';
import 'package:gita_companion/app/providers.dart';
import 'package:gita_companion/core/content/sqlite_content_repository.dart';
import 'package:gita_companion/core/db/user_database.dart';
import 'package:gita_companion/core/search/search_service.dart';
import 'package:gita_companion/core/settings/app_settings.dart';
import 'package:gita_companion/core/study/study_repository.dart';
import 'package:go_router/go_router.dart';

import 'support/audio_fakes.dart';
import 'support/fake_server.dart';
import 'support/pack.dart';
import 'widgets_test.dart' show MemorySettingsRepository;

/// Accessibility audit of every main screen, in light and dark themes:
/// - tap targets at least 48x48 (Android guideline);
/// - every tap target has a label TalkBack can read;
/// - text contrast at least WCAG AA (4.5:1, 3:1 for large text);
/// - no layout overflow at the largest system text size (200%).
void main() {
  late SqliteContentRepository content;
  late SqliteSearchService search;
  setUpAll(() {
    final db = openPackWithSampleAi();
    content = SqliteContentRepository(db);
    search = SqliteSearchService(db, verseExists: content.readingOrder().toSet().contains);
  });

  const screens = {
    'home': '/',
    'chapters': '/chapters',
    'chapter': '/chapters/2',
    'reader': '/verse/2.47',
    'search': '/search',
    'my gita': '/my',
    'revision': '/my/revise',
    'daily practice': '/practice',
    'downloads': '/settings/downloads',
    'settings': '/settings',
    'teacher': '/tutor',
  };

  Future<void> pump(
    WidgetTester tester,
    String route, {
    required ThemeMode theme,
    double systemTextScale = 1.0,
    String language = 'en',
  }) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    tester.platformDispatcher.textScaleFactorTestValue = systemTextScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final s = AppSettings(onboardingDone: true, themeMode: theme, uiLanguage: language);
    final userDb = UserDatabase.memory();
    addTearDown(userDb.close);
    // Some study data, so lists and the revision card are populated.
    await tester.runAsync(() async {
      final study = StudyRepository(userDb, clock: () => DateTime(2026, 9, 28));
      await study.setBookmarked('2.47', true);
      await study.saveNote(verseId: '2.47', kind: NoteKind.question, body: 'What counts as a fruit?');
      await study.setNeedsRevision('2.47', true);
      await study.markRead('2.47');
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentRepositoryProvider.overrideWithValue(content),
          searchServiceProvider.overrideWithValue(search),
          settingsRepositoryProvider.overrideWithValue(MemorySettingsRepository()..saved = s),
          initialSettingsProvider.overrideWithValue(s),
          userDatabaseProvider.overrideWithValue(userDb),
          clockProvider.overrideWithValue(() => DateTime(2026, 10, 1)),
          ...TestAudio().overrides,
          ...FakeGitaServer().overrides(),
        ],
        child: const GitaApp(),
      ),
    );
    await tester.pumpAndSettle();
    GoRouterHelper(tester.element(find.byType(Scaffold).first)).go(route);
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    if (route == '/search') {
      await tester.enterText(find.byType(TextField), 'How do I control my anger?');
      await tester.pumpAndSettle();
    }
  }

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    for (final MapEntry(key: name, value: route) in screens.entries) {
      testWidgets('$name (${theme.name}): tap targets, labels, contrast', (tester) async {
        final handle = tester.ensureSemantics();
        await pump(tester, route, theme: theme);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  }

  for (final language in ['en', 'te']) {
    for (final MapEntry(key: name, value: route) in screens.entries) {
      testWidgets('$name ($language): no overflow at 200% system text size', (tester) async {
        await pump(tester, route, theme: ThemeMode.light, systemTextScale: 2.0, language: language);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
