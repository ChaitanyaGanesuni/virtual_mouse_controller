import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/app/app.dart';
import 'package:gita_companion/app/providers.dart';
import 'package:gita_companion/core/api/token_store.dart';
import 'package:gita_companion/core/content/sqlite_content_repository.dart';
import 'package:gita_companion/core/db/user_database.dart';
import 'package:gita_companion/core/search/search_service.dart';
import 'package:gita_companion/core/settings/app_settings.dart';
import 'package:gita_companion/core/study/study_repository.dart';
import 'package:go_router/go_router.dart';

import 'support/audio_fakes.dart';
import 'support/fake_sync_server.dart';
import 'support/finders.dart';
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

  var now = DateTime(2026, 10, 6, 9);
  late UserDatabase userDb;
  setUp(() {
    now = DateTime(2026, 10, 6, 9);
    userDb = UserDatabase.memory();
  });
  tearDown(() => userDb.close());

  StudyRepository study() => StudyRepository(userDb, clock: () => now);

  Future<void> pumpAt(
    WidgetTester tester,
    String route, {
    List<Override> extra = const [],
    UserDatabase? db,
    AppSettings settings = const AppSettings(onboardingDone: true),
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentRepositoryProvider.overrideWithValue(content),
          searchServiceProvider.overrideWithValue(search),
          settingsRepositoryProvider.overrideWithValue(MemorySettingsRepository()..saved = settings),
          initialSettingsProvider.overrideWithValue(settings),
          userDatabaseProvider.overrideWithValue(db ?? userDb),
          clockProvider.overrideWithValue(() => now),
          ...TestAudio().overrides,
          ...extra,
        ],
        child: const GitaApp(),
      ),
    );
    await tester.pumpAndSettle();
    GoRouterHelper(tester.element(find.byType(Scaffold).first)).go(route);
    await tester.pumpAndSettle();
  }

  // Database writes complete outside the fake-async zone.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('from the reader: bookmark, favourite, revise and a note show up in My Gita', (tester) async {
    await pumpAt(tester, '/verse/2.47');
    await settle(tester);
    await tester.tap(find.byTooltip('Bookmark'));
    await tester.tap(find.byTooltip('Add to favourites'));
    await tester.tap(find.widgetWithText(FilterChip, 'Revise'));
    await settle(tester);
    expect(find.byTooltip('Remove bookmark'), findsOneWidget);

    await tester.tap(find.byTooltip('Add a note'));
    await tester.pumpAndSettle();
    expect(find.text('Note on Verse 2.47'), findsOneWidget);
    await tester.tap(find.text('Question'));
    await tester.enterText(find.byType(TextField), 'What counts as a fruit?');
    await tester.tap(find.text('Save'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('What counts as a fruit?'), 200, scrollable: mainList());
    expect(find.text('What counts as a fruit?'), findsOneWidget);

    final v = await tester.runAsync(() => study().verse('2.47'));
    expect((v!.bookmarked, v.favorite, v.needsRevision), (true, true, true));
    expect(v.notes.single.kind, 'question');

    GoRouterHelper(tester.element(find.byType(Scaffold).first)).go('/my');
    await settle(tester);
    expect(find.textContaining('1 of 700 verses read'), findsOneWidget);
    expect(find.text('Nothing to revise today.'), findsOneWidget, reason: 'first due tomorrow');
    await tester.tap(find.text('Saved'));
    await settle(tester);
    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text('Verse 2.47'), findsNWidgets(2));
    await tester.tap(find.text('Notes'));
    await settle(tester);
    expect(find.text('What counts as a fruit?'), findsOneWidget);
    expect(find.text('Question · Verse 2.47'), findsOneWidget);
  });

  testWidgets('home: continue where you stopped, and revision when cards are due', (tester) async {
    await tester.runAsync(() async {
      await study().markRead('3.19');
      await study().setNeedsRevision('2.47', true);
    });
    now = now.add(const Duration(days: 1));
    await pumpAt(tester, '/');
    await settle(tester);
    expect(find.text('Continue at Verse 3.19'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('1 verse to revise today'), 200, scrollable: mainList());
    expect(find.text('1 verse to revise today'), findsOneWidget);
  });

  testWidgets('a revision session: recall, reveal, grade', (tester) async {
    await tester.runAsync(() => study().setNeedsRevision('2.47', true));
    now = now.add(const Duration(days: 2)); // both cards due
    await pumpAt(tester, '/my/revise');
    await settle(tester);
    expect(find.text('2 left'), findsOneWidget);
    expect(find.text('What does this verse teach?'), findsOneWidget);
    await tester.tap(find.text('Show the meaning'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Good'), 200, scrollable: mainList());
    expect(find.text('How well did you remember?'), findsOneWidget);
    expect(find.text('2 days'), findsOneWidget, reason: 'Good moves up the ladder');
    await scrollToAndTap(tester, find.text('Good'));
    await settle(tester);

    expect(find.text('How could you apply this verse today?'), findsOneWidget);
    await tester.tap(find.text('Show the meaning'));
    await tester.pumpAndSettle();
    await scrollToAndTap(tester, find.text('Again'));
    await settle(tester);
    expect(find.text('1 left'), findsOneWidget, reason: 'Again comes back in this session');
    await tester.tap(find.text('Show the meaning'));
    await tester.pumpAndSettle();
    await scrollToAndTap(tester, find.text('Easy'));
    await settle(tester);
    expect(find.textContaining('2 cards revised'), findsOneWidget);
    final reviews = await tester.runAsync(() => userDb.select(userDb.revisionReviewsTable).get());
    expect(reviews!.map((r) => r.rating), unorderedEquals([3, 1, 4]));
  });

  testWidgets('daily practice: steps and a private journal', (tester) async {
    await pumpAt(tester, '/practice');
    await settle(tester);
    expect(find.text('0 of 4 steps today'), findsOneWidget);
    await tester.tap(find.text('Mark as done').first);
    await settle(tester);
    expect(find.text('1 of 4 steps today'), findsOneWidget);

    final journal = find.widgetWithText(TextField, 'A few lines for yourself…');
    await tester.scrollUntilVisible(journal, 200, scrollable: mainList());
    await tester.enterText(journal, 'Less worry today.');
    await scrollToAndTap(tester, find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);
    final day = await tester.runAsync(() => study().practice('2026-10-06'));
    expect(day!.journal, 'Less worry today.');
    expect(day.listenedAt, isNotNull);
  });

  testWidgets('settings: turn on sync, get a recovery code, restore on a new installation', (tester) async {
    final server = FakeSyncServer();
    List<Override> online(TokenStore tokens) => [
      httpClientProvider.overrideWithValue(server.client),
      tokenStoreProvider.overrideWithValue(tokens),
      builtInServerAddressProvider.overrideWithValue('https://gita.test'),
    ];
    await tester.runAsync(() => study().setBookmarked('2.47', true));
    await pumpAt(tester, '/settings', extra: online(MemoryTokenStore()));
    await tester.scrollUntilVisible(find.text('Sync my study data'), 200, scrollable: mainList());
    await scrollToAndTap(tester, find.text('Sync my study data'));
    await settle(tester);
    expect(find.text('Keep your data safe'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Get a recovery code'));
    await settle(tester);
    expect(find.text('Your recovery code'), findsOneWidget);
    final code = (tester.widget<SelectableText>(find.byType(SelectableText).last)).data!;
    expect(code, matches(RegExp(r'^[A-Z0-9]{4}(-[A-Z0-9]{4}){5}$')));
    await tester.tap(find.text('I have saved it'));
    await settle(tester);
    expect(server.stored(server.lastUser, 'bookmark').keys, ['2.47']);

    // A new installation: empty database, no credentials.
    final fresh = UserDatabase.memory();
    addTearDown(fresh.close);
    await tester.pumpWidget(const SizedBox());
    await pumpAt(tester, '/settings', db: fresh, extra: online(MemoryTokenStore()));
    await scrollToAndTap(tester, find.text('Restore from a recovery code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), code.toLowerCase());
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await settle(tester);
    expect(find.text('Your data has been restored.'), findsOneWidget);
    final v = await tester.runAsync(() => StudyRepository(fresh).verse('2.47'));
    expect(v!.bookmarked, isTrue);
  });
}
