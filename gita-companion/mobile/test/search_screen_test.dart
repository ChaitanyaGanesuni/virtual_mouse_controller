import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/app/app.dart';
import 'package:gita_companion/app/providers.dart';
import 'package:gita_companion/core/content/sqlite_content_repository.dart';
import 'package:gita_companion/core/search/search_service.dart';
import 'package:gita_companion/core/settings/app_settings.dart';
import 'package:go_router/go_router.dart';

import 'support/audio_fakes.dart';
import 'support/pack.dart';
import 'widgets_test.dart' show MemorySettingsRepository;
import 'support/finders.dart';

void main() {
  late SqliteContentRepository content;
  late SqliteSearchService search;
  setUpAll(() {
    final db = openPackWithSampleAi();
    content = SqliteContentRepository(db);
    search = SqliteSearchService(db, verseExists: content.readingOrder().toSet().contains);
  });

  Future<void> pumpSearch(WidgetTester tester, {String language = 'en'}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final s = AppSettings(onboardingDone: true, uiLanguage: language);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentRepositoryProvider.overrideWithValue(content),
          searchServiceProvider.overrideWithValue(search),
          settingsRepositoryProvider.overrideWithValue(MemorySettingsRepository()..saved = s),
          initialSettingsProvider.overrideWithValue(s),
          ...TestAudio().overrides,
          clockProvider.overrideWithValue(() => DateTime(2026, 10, 1)),
        ],
        child: const GitaApp(),
      ),
    );
    await tester.pumpAndSettle();
    GoRouterHelper(tester.element(find.byType(Scaffold).first)).go('/search');
    await tester.pumpAndSettle();
  }

  testWidgets('a question finds verses by meaning and names its topics', (tester) async {
    await pumpSearch(tester);
    await tester.enterText(find.byType(TextField), 'How do I control my anger?');
    await tester.pumpAndSettle();

    expect(find.text('Related to:'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Anger (krodha)'), findsOneWidget);
    final first8 = search.search('How do I control my anger?').take(8).map((h) => h.verseId);
    expect(first8, containsAll(['2.62', '2.63']));
    expect(find.textContaining('· Topic'), findsWidgets);

    await tester.tap(find.widgetWithText(ActionChip, 'Anger (krodha)'));
    await tester.pumpAndSettle();
    expect(find.text('Verses on this topic, best first'), findsOneWidget);
    expect(search.topic('anger').map((h) => h.verseId), containsAll(['2.62', '2.63', '3.37']));
  });

  testWidgets('with no query, topics can be browsed', (tester) async {
    await pumpSearch(tester);
    expect(find.text('Browse by topic'), findsOneWidget);
    final chip = find.widgetWithText(ActionChip, 'Anger (krodha)');
    await tester.scrollUntilVisible(chip, 200, scrollable: mainList());
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('Verses on this topic, best first'), findsOneWidget);
    expect(find.textContaining('· Topic'), findsWidgets);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Browse by topic'), findsOneWidget);
  });

  testWidgets('topics are named in Telugu for Telugu readers', (tester) async {
    await pumpSearch(tester, language: 'te');
    await tester.enterText(find.byType(TextField), 'కోపం ఎలా తగ్గించుకోవాలి');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ActionChip, 'కోపం (krodha)'), findsOneWidget);
  });

  test('topics in the service', () {
    expect(search.topics().length, greaterThanOrEqualTo(60));
    expect(search.conceptsOf('I am anxious about results').map((c) => c.id), isNotEmpty);
    expect(search.topic('no-such-topic'), isEmpty);
  });

  test('a reference inside a question comes first', () {
    expect(search.search('What does 2.47 say about duty?').first.verseId, '2.47');
    expect(search.search('explain chapter 18 verse 66').first.verseId, '18.66');
  });
}
