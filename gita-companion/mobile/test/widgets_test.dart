import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/app/app.dart';
import 'package:gita_companion/app/providers.dart';
import 'package:gita_companion/core/content/models.dart';
import 'package:gita_companion/core/content/sqlite_content_repository.dart';
import 'package:gita_companion/core/settings/app_settings.dart';
import 'package:go_router/go_router.dart';

import 'support/pack.dart';

class MemorySettingsRepository implements SettingsRepository {
  AppSettings saved = const AppSettings();

  @override
  Future<AppSettings> load() async => saved;

  @override
  Future<void> save(AppSettings settings) async => saved = settings;
}

void main() {
  late SqliteContentRepository content;
  setUpAll(() => content = openRealRepository());

  Future<MemorySettingsRepository> pumpApp(WidgetTester tester, AppSettings settings) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final store = MemorySettingsRepository()..saved = settings;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentRepositoryProvider.overrideWithValue(content),
          settingsRepositoryProvider.overrideWithValue(store),
          initialSettingsProvider.overrideWithValue(settings),
          clockProvider.overrideWithValue(() => DateTime(2026, 10, 1)),
        ],
        child: const GitaApp(),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  const ready = AppSettings(onboardingDone: true);

  testWidgets('first launch shows onboarding; Begin saves choices and opens Home', (tester) async {
    final store = await pumpApp(tester, const AppSettings());
    expect(find.text('Welcome'), findsOneWidget);

    await tester.tap(find.text('Telugu script'));
    await tester.pumpAndSettle();
    expect(find.textContaining('కర్మణ్యేవాధికారస్తే'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Begin'), 200);
    await tester.tap(find.text('Begin'));
    await tester.pumpAndSettle();
    expect(store.saved.onboardingDone, isTrue);
    expect(store.saved.verseScript, VerseScript.telugu);
    expect(find.text("TODAY'S VERSE"), findsOneWidget);
  });

  testWidgets('Home shows the verse of the day and opens it', (tester) async {
    await pumpApp(tester, ready);
    final today = content.verseOfTheDay(DateTime(2026, 10, 1));
    expect(find.textContaining('Verse ${today.id}'), findsOneWidget);

    await tester.tap(find.textContaining('Verse ${today.id}'));
    await tester.pumpAndSettle();
    expect(find.textContaining(today.sanskrit.split(' ').first), findsWidgets);
    expect(find.textContaining('No translation is installed yet'), findsOneWidget);
  });

  testWidgets('Chapters list → chapter → verse → next verse', (tester) async {
    await pumpApp(tester, ready);
    await tester.tap(find.text('All 18 chapters'));
    await tester.pumpAndSettle();
    expect(find.text('साङ्ख्ययोग'), findsOneWidget);

    await tester.tap(find.text('साङ्ख्ययोग'));
    await tester.pumpAndSettle();
    expect(find.text('Chapter 2'), findsOneWidget);
    expect(find.text('72 verses'), findsOneWidget);
    expect(
      find.textContaining('AI-assisted'),
      findsOneWidget,
      reason: 'one label covers gloss, theme and summary',
    );

    await tester.tap(find.text('2.1'));
    await tester.pumpAndSettle();
    expect(find.text('Verse 2.1'), findsOneWidget);
    expect(find.text('सञ्जय उवाच'), findsOneWidget);
    expect(find.textContaining('\u00A0॥'), findsWidgets, reason: 'danda stays with its word');

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Verse 2.2'), findsOneWidget);
  });

  testWidgets('13.0 is explained as non-canonical', (tester) async {
    await pumpApp(tester, ready);
    final router = tester.element(find.byType(Scaffold).first);
    GoRouterHelper(router).go('/verse/13.0');
    await tester.pumpAndSettle();
    expect(find.textContaining('not counted among the 700 verses'), findsOneWidget);
  });

  testWidgets('corrected verses show their pending review status', (tester) async {
    await pumpApp(tester, ready);
    GoRouterHelper(tester.element(find.byType(Scaffold).first)).go('/verse/16.20');
    await tester.pumpAndSettle();
    expect(find.textContaining('awaiting scholarly review'), findsOneWidget);
  });

  testWidgets('invalid verse links fall back to the chapter list', (tester) async {
    await pumpApp(tester, ready);
    GoRouterHelper(tester.element(find.byType(Scaffold).first)).go('/verse/2.73');
    await tester.pumpAndSettle();
    expect(find.text('Chapters'), findsOneWidget);
  });

  testWidgets('Telugu UI language is independent of the verse script', (tester) async {
    await pumpApp(tester, ready.copyWith(uiLanguage: 'te', verseScript: VerseScript.devanagari));
    expect(find.text('నేటి శ్లోకం'), findsOneWidget);
    expect(find.text('श्रीमद्भगवद्गीता'), findsOneWidget);
  });

  testWidgets('Settings: switching script and theme persists', (tester) async {
    final store = await pumpApp(tester, ready);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(store.saved.themeMode, ThemeMode.dark);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Roman (IAST)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Roman (IAST)'));
    await tester.pumpAndSettle();
    expect(store.saved.verseScript, VerseScript.iast);

    await tester.ensureVisible(find.text('Sources and licences'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sources and licences'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bhagavad Gītā, Sanskrit text'), findsOneWidget);
  });

  testWidgets('dark theme and large text render without overflow', (tester) async {
    await pumpApp(tester, ready.copyWith(themeMode: ThemeMode.dark, textScale: 1.6));
    expect(tester.takeException(), isNull);
    GoRouterHelper(tester.element(find.byType(Scaffold).first)).go('/verse/11.1');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
