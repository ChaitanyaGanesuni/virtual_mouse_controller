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
import 'package:gita_companion/core/settings/app_settings.dart';
import 'package:go_router/go_router.dart';

import '../support/pack.dart';
import '../widgets_test.dart' show MemorySettingsRepository;

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

  final content = openRealRepository();

  Future<void> shot(WidgetTester tester, String name, AppSettings settings, {String? route}) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentRepositoryProvider.overrideWithValue(content),
          settingsRepositoryProvider.overrideWithValue(MemorySettingsRepository()..saved = settings),
          initialSettingsProvider.overrideWithValue(settings),
          clockProvider.overrideWithValue(() => DateTime(2026, 10, 1)),
        ],
        child: const GitaApp(),
      ),
    );
    await tester.pumpAndSettle();
    if (route != null) {
      GoRouterHelper(tester.element(find.byType(Scaffold).first)).go(route);
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
}
