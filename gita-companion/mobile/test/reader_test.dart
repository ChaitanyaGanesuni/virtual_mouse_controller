import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/app/app.dart';
import 'package:gita_companion/app/providers.dart';
import 'package:gita_companion/core/content/models.dart';
import 'package:gita_companion/core/content/sqlite_content_repository.dart';
import 'package:gita_companion/core/search/search_service.dart';
import 'package:gita_companion/core/settings/app_settings.dart';
import 'package:go_router/go_router.dart';

import 'support/pack.dart';
import 'widgets_test.dart' show MemorySettingsRepository;

void main() {
  late SqliteContentRepository content;
  late SqliteSearchService search;
  setUpAll(() {
    final db = openPackWithSampleAi();
    content = SqliteContentRepository(db);
    search = SqliteSearchService(db, verseExists: content.readingOrder().toSet().contains);
  });

  Future<MemorySettingsRepository> pumpAt(WidgetTester tester, String route, {AppSettings? settings}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final s = settings ?? const AppSettings(onboardingDone: true);
    final store = MemorySettingsRepository()..saved = s;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentRepositoryProvider.overrideWithValue(content),
          searchServiceProvider.overrideWithValue(search),
          settingsRepositoryProvider.overrideWithValue(store),
          initialSettingsProvider.overrideWithValue(s),
          clockProvider.overrideWithValue(() => DateTime(2026, 10, 1)),
        ],
        child: const GitaApp(),
      ),
    );
    await tester.pumpAndSettle();
    GoRouterHelper(tester.element(find.byType(Scaffold).first)).go(route);
    await tester.pumpAndSettle();
    return store;
  }

  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
  }

  testWidgets('explanation modes, AI labelling with model name, Sanskrit terms', (tester) async {
    await pumpAt(tester, '/verse/2.47');
    await scrollTo(tester, find.text('You have a right to your actions, never to their fruits.'));
    expect(find.textContaining('AI-generated (test-model)'), findsWidgets);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Deeper'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Deep: the verse separates'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Sanskrit terms'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Sanskrit terms'));
    await tester.pumpAndSettle();
    expect(find.text('karma'), findsOneWidget);
    expect(find.text("Action, especially one's duty."), findsOneWidget);
  });

  testWidgets('word by word is shown with its source label', (tester) async {
    await pumpAt(tester, '/verse/2.47');
    await scrollTo(tester, find.text('WORD BY WORD'));
    expect(find.textContaining('in action'), findsOneWidget);
  });

  testWidgets('Telugu explanation where available, English fallback is announced', (tester) async {
    await pumpAt(
      tester,
      '/verse/2.47',
      settings: const AppSettings(onboardingDone: true, explanationLanguage: 'te'),
    );
    await scrollTo(tester, find.text('కర్మ చేయడంలోనే నీకు అధికారం ఉంది.'));
    expect(find.textContaining('Not yet available'), findsNothing);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Story'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Story'));
    await tester.pumpAndSettle();
    expect(find.text('A gardener waters the seed and trusts the season.'), findsOneWidget);
    expect(find.text('Not yet available in Telugu; showing English.'), findsOneWidget);
  });

  testWidgets('switching explanation language from the verse screen persists', (tester) async {
    final store = await pumpAt(tester, '/verse/2.47');
    await scrollTo(tester, find.widgetWithText(SegmentedButton<String>, 'Telugu'));
    await tester.tap(find.text('Telugu').last);
    await tester.pumpAndSettle();
    expect(store.saved.explanationLanguage, 'te');
  });

  testWidgets('verses without explanations say so honestly', (tester) async {
    await pumpAt(tester, '/verse/2.48');
    await scrollTo(tester, find.textContaining('have not been generated yet'));
    expect(find.textContaining('AI-generated'), findsNothing);
  });

  testWidgets('swiping moves through verses and across chapters', (tester) async {
    await pumpAt(tester, '/verse/1.47');
    expect(find.text('Verse 1.47'), findsOneWidget);
    expect(find.text('Chapter 1 · 47 of 47'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Verse 2.1'), findsOneWidget);

    await tester.tap(find.text('Previous'));
    await tester.pumpAndSettle();
    expect(find.text('Verse 1.47'), findsOneWidget);
  });

  testWidgets('the selected explanation mode is kept while moving between verses', (tester) async {
    await pumpAt(tester, '/verse/2.47');
    await scrollTo(tester, find.widgetWithText(ChoiceChip, 'Deeper'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Deeper'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Verse 2.48'), findsOneWidget);
    await scrollTo(tester, find.widgetWithText(ChoiceChip, 'Deeper'));
    final chip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Deeper'));
    expect(chip.selected, isTrue);
  });

  testWidgets('script and text size can be changed from the reader', (tester) async {
    final store = await pumpAt(tester, '/verse/2.47');
    await tester.tap(find.byTooltip('Script'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Telugu script').last);
    await tester.pumpAndSettle();
    expect(store.saved.verseScript, VerseScript.telugu);
    expect(find.textContaining('కర్మణ్యేవాధికారస్తే'), findsOneWidget);

    await tester.tap(find.byTooltip('Larger text'));
    await tester.pumpAndSettle();
    expect(store.saved.textScale, closeTo(1.1, 1e-9));
  });

  testWidgets('chapter screen shows theme, summary, estimates and starts reading', (tester) async {
    await pumpAt(tester, '/chapters/2');
    expect(find.text('CENTRAL THEME'.toLowerCase()), findsNothing);
    expect(find.text('Central theme'), findsOneWidget);
    expect(find.textContaining('eternal Self'), findsOneWidget);
    expect(find.textContaining('About'), findsNWidgets(2));
    expect(find.text('Read more'), findsOneWidget);

    await tester.tap(find.text('Start reading'));
    await tester.pumpAndSettle();
    expect(find.text('Verse 2.1'), findsOneWidget);
  });

  testWidgets('search from home: romanised query → result → verse', (tester) async {
    await pumpAt(tester, '/');
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'phaleshu');
    await tester.pumpAndSettle();
    expect(find.textContaining('2.47 · Transliteration'), findsOneWidget);

    await tester.tap(find.textContaining('2.47 · Transliteration'));
    await tester.pumpAndSettle();
    expect(find.text('Verse 2.47'), findsOneWidget);
  });

  testWidgets('search: reference and no-result states', (tester) async {
    await pumpAt(tester, '/search');
    await tester.enterText(find.byType(TextField), '18.66');
    await tester.pumpAndSettle();
    expect(find.textContaining('18.66 · Verse number'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzzqqq');
    await tester.pumpAndSettle();
    expect(find.text('No verses found.'), findsOneWidget);
  });
}
