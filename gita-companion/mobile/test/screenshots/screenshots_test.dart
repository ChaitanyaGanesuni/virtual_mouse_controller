// Renders the main screens to PNG with the real bundled fonts, for design
// review. Not part of the regular suite:
//   flutter test --tags screenshots --update-goldens test/screenshots
@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/app/app.dart';
import 'package:gita_companion/app/providers.dart';
import 'package:gita_companion/core/content/models.dart';
import 'package:gita_companion/core/content/sqlite_content_repository.dart';
import 'package:gita_companion/core/search/search_service.dart';
import 'package:gita_companion/core/settings/app_settings.dart';
import 'package:go_router/go_router.dart';

import '../support/audio_fakes.dart';
import '../support/fake_server.dart';
import '../support/pack.dart';
import '../widgets_test.dart' show MemorySettingsRepository;
import '../support/finders.dart';

import 'package:gita_companion/core/db/user_database.dart';
import 'package:gita_companion/core/study/study_repository.dart';

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _loadFont('NotoSerifDevanagari', ['assets/fonts/NotoSerifDevanagari.ttf']);
    await _loadFont('NotoSansTelugu', ['assets/fonts/NotoSansTelugu.ttf']);
    await _loadFont('NotoSerif', ['assets/fonts/NotoSerif.ttf']);
    // Stand-in for the platform UI font (Roboto on Android).
    await _loadFont('Roboto', ['assets/fonts/NotoSerif.ttf']);
  });

  final aiDb = openPackWithSampleAi();
  final content = SqliteContentRepository(aiDb);
  final search = SqliteSearchService(aiDb, verseExists: content.readingOrder().toSet().contains);

  Future<void> shot(
    WidgetTester tester,
    String name,
    AppSettings settings, {
    String? route,
    Finder? scrollTo,
    String? type,
    String? tap,
    bool back = false,
    FakeGitaServer? server,
    Future<void> Function(StudyRepository study)? seed,
  }) async {
    final userDb = UserDatabase.memory();
    addTearDown(userDb.close);
    if (seed != null) {
      // Written a few days earlier, so revision cards are due "today".
      await tester.runAsync(() => seed(StudyRepository(userDb, clock: () => DateTime(2026, 9, 28, 9))));
    }
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentRepositoryProvider.overrideWithValue(content),
          searchServiceProvider.overrideWithValue(search),
          settingsRepositoryProvider.overrideWithValue(MemorySettingsRepository()..saved = settings),
          initialSettingsProvider.overrideWithValue(settings),
          ...TestAudio().overrides,
          ...(server ?? FakeGitaServer()).overrides(),
          clockProvider.overrideWithValue(() => DateTime(2026, 10, 1)),
          userDatabaseProvider.overrideWithValue(userDb),
        ],
        child: const GitaApp(),
      ),
    );
    await tester.pumpAndSettle();
    if (route != null) {
      GoRouterHelper(tester.element(find.byType(Scaffold).first)).go(route);
      await tester.pumpAndSettle();
    }
    if (type != null) {
      await tester.enterText(find.byType(TextField), type);
      await tester.pumpAndSettle();
    }
    if (tap != null) {
      await tester.tap(find.text(tap));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      if (back) {
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    }
    if (scrollTo != null) {
      await tester.scrollUntilVisible(scrollTo, 300, scrollable: mainList());
      await tester.drag(mainList(), const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    await expectLater(find.byType(GitaApp), matchesGoldenFile('out/$name.png'));
  }

  const ready = AppSettings(onboardingDone: true);

  testWidgets('home light', (t) => shot(t, 'home_light', ready));
  testWidgets(
    'home dark telugu',
    (t) => shot(
      t,
      'home_dark_telugu_ui',
      ready.copyWith(themeMode: ThemeMode.dark, uiLanguage: 'te', verseScript: VerseScript.telugu),
    ),
  );
  testWidgets('onboarding', (t) => shot(t, 'onboarding', const AppSettings()));
  testWidgets('chapters', (t) => shot(t, 'chapters', ready, route: '/chapters'));
  testWidgets('chapter 2', (t) => shot(t, 'chapter_2', ready, route: '/chapters/2'));
  testWidgets('verse 2.47', (t) => shot(t, 'verse_2_47', ready, route: '/verse/2.47'));
  testWidgets(
    'verse 1.28 dark',
    (t) => shot(t, 'verse_1_28_dark', ready.copyWith(themeMode: ThemeMode.dark), route: '/verse/1.28'),
  );
  testWidgets('settings', (t) => shot(t, 'settings', ready, route: '/settings'));
  testWidgets(
    'reader understand',
    (t) => shot(t, 'reader_2_47_understand', ready, route: '/verse/2.47', scrollTo: find.text('UNDERSTAND')),
  );
  testWidgets(
    'reader telugu dark',
    (t) => shot(
      t,
      'reader_2_47_telugu_dark',
      ready.copyWith(themeMode: ThemeMode.dark, verseScript: VerseScript.telugu, explanationLanguage: 'te'),
      route: '/verse/2.47',
      scrollTo: find.text('UNDERSTAND'),
    ),
  );
  testWidgets('search', (t) => shot(t, 'search_phaleshu', ready, route: '/search', type: 'phaleshu'));
  testWidgets('search english', (t) => shot(t, 'search_anxiety', ready, route: '/search', type: 'anxiety'));
  testWidgets(
    'search question',
    (t) => shot(t, 'search_question_anger', ready, route: '/search', type: 'How do I control my anger?'),
  );
  testWidgets(
    'search question telugu',
    (t) => shot(
      t,
      'search_question_telugu_dark',
      ready.copyWith(themeMode: ThemeMode.dark, uiLanguage: 'te', translationLanguage: 'te'),
      route: '/search',
      type: 'కోపం ఎలా తగ్గించుకోవాలి',
    ),
  );
  testWidgets('search topics', (t) => shot(t, 'search_topics', ready, route: '/search'));
  Future<void> studied(StudyRepository s) async {
    final translation = content.verse('2.47')!.texts.firstWhere((t) => t.kind == 'translation');
    for (final v in ['2.11', '2.12', '2.13', '2.14', '2.20', '2.47', '2.48', '3.19', '6.35']) {
      await s.markRead(v);
    }
    await s.setBookmarked('2.47', true);
    await s.setFavorite('2.47', true);
    await s.setUnderstood('2.20', true);
    await s.setNeedsRevision('2.47', true);
    await s.setNeedsRevision('6.35', true);
    await s.addHighlight(
      verseId: '2.47',
      textId: translation.id,
      start: 0,
      end: translation.body.indexOf(';'),
    );
    await s.saveNote(
      verseId: '2.47',
      kind: NoteKind.question,
      body: 'Does "not the fruits" mean I should not plan?',
    );
  }

  testWidgets('my gita', (t) => shot(t, 'my_gita_overview', ready, route: '/my', seed: studied));
  testWidgets(
    'reader with study data',
    (t) => shot(
      t,
      'reader_2_47_study',
      ready,
      route: '/verse/2.47',
      seed: studied,
      scrollTo: find.text('TRANSLATION'),
    ),
  );
  testWidgets(
    'revision card',
    (t) => shot(t, 'revision_card', ready, route: '/my/revise', seed: studied, tap: 'Show the meaning'),
  );
  testWidgets('daily practice', (t) => shot(t, 'daily_practice', ready, route: '/practice', seed: studied));
  testWidgets(
    'daily practice telugu dark',
    (t) => shot(
      t,
      'daily_practice_telugu_dark',
      ready.copyWith(themeMode: ThemeMode.dark, uiLanguage: 'te', verseScript: VerseScript.telugu),
      route: '/practice',
    ),
  );
  testWidgets(
    'settings sync',
    (t) => shot(
      t,
      'settings_sync',
      ready,
      route: '/settings',
      scrollTo: find.text('Restore from a recovery code'),
    ),
  );
  testWidgets('player', (t) => shot(t, 'player_recitation', ready, route: '/verse/2.47', tap: 'Recite'));
  testWidgets(
    'player dark',
    (t) => shot(
      t,
      'player_dark',
      ready.copyWith(themeMode: ThemeMode.dark),
      route: '/chapters/2',
      tap: 'Start listening',
    ),
  );
  testWidgets(
    'mini player',
    (t) => shot(t, 'mini_player', ready, route: '/verse/2.47', tap: 'Recite', back: true),
  );

  final english = FakeGitaServer.answer(
    text:
        'Krishna separates two things: the action, which is yours to do, and its result, which is not '
        'yours to command (BG 2.47).\n\n'
        '- Do the work fully and well.\n'
        '- Let go of the demand that it turn out a particular way.\n'
        '- Do not use this as a reason to stop acting.\n\n'
        'The next verse calls this evenness, samatva (BG 2.48).',
    verses: ['2.47', '2.48'],
    uncertain: ['How literally to read adhikāra ("right" or "concern") here'],
  );
  final telugu = FakeGitaServer.answer(
    text:
        'కర్మ చేయడం మీ బాధ్యత; దాని ఫలితం మీ ఆధీనంలో లేదు (BG 2.47).\n\n'
        'పని మీద పూర్తి శ్రద్ధ పెట్టండి, ఫలితంపై పట్టుదల వదిలేయండి. అలాగని పని మానేయకూడదు.',
  );
  testWidgets(
    'tutor answer',
    (t) => shot(
      t,
      'tutor_answer',
      ready,
      route: '/tutor?verse=2.47',
      tap: 'Explain with the AI teacher',
      server: FakeGitaServer()..answers.add(english),
    ),
  );
  testWidgets(
    'tutor answer telugu dark',
    (t) => shot(
      t,
      'tutor_answer_telugu_dark',
      ready.copyWith(themeMode: ThemeMode.dark, uiLanguage: 'te', explanationLanguage: 'te'),
      route: '/tutor?verse=2.47',
      tap: 'AI గురువుతో వివరించండి',
      server: FakeGitaServer()..answers.add(telugu),
    ),
  );
  testWidgets('tutor empty', (t) => shot(t, 'tutor_empty', ready, route: '/tutor'));
  testWidgets(
    'settings teacher',
    (t) => shot(t, 'settings_teacher', ready, route: '/settings', scrollTo: find.text('Server address')),
  );
}
