import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/app/app.dart';
import 'package:gita_companion/app/providers.dart';
import 'package:gita_companion/core/content/sqlite_content_repository.dart';
import 'package:gita_companion/core/search/search_service.dart';
import 'package:gita_companion/core/settings/app_settings.dart';
import 'package:go_router/go_router.dart';

import '../support/audio_fakes.dart';
import '../support/finders.dart';
import '../support/pack.dart';
import '../widgets_test.dart' show MemorySettingsRepository;

/// Frame work (build, layout, paint) while scrolling the heaviest screens.
/// The deterministic check is how many widgets are rebuilt per frame: a list
/// that stops being lazy, or a provider that rebuilds a whole screen while
/// scrolling, shows up there at once.
/// Measured on the CI machine without a GPU, so these are relative numbers
/// that catch regressions (for example a list that stops being lazy); real
/// frame rates are checked on a phone with `flutter run --profile` (see
/// docs/RELEASE-CHECKLIST.md).
void main() {
  late SqliteContentRepository content;
  late SqliteSearchService search;
  setUpAll(() {
    final db = openPackWithSampleAi();
    content = SqliteContentRepository(db);
    search = SqliteSearchService(db, verseExists: content.readingOrder().toSet().contains);
  });

  Future<(List<double>, double)> scrollFrames(
    WidgetTester tester,
    String route, {
    String? type,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final s = AppSettings(onboardingDone: true, textScale: textScale);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentRepositoryProvider.overrideWithValue(content),
          searchServiceProvider.overrideWithValue(search),
          settingsRepositoryProvider.overrideWithValue(MemorySettingsRepository()..saved = s),
          initialSettingsProvider.overrideWithValue(s),
          ...TestAudio().overrides,
        ],
        child: const GitaApp(),
      ),
    );
    await tester.pumpAndSettle();
    GoRouterHelper(tester.element(find.byType(Scaffold).first)).go(route);
    await tester.pumpAndSettle();
    if (type != null) {
      await tester.enterText(find.byType(TextField), type);
      await tester.pumpAndSettle();
    }
    var builds = 0;
    debugOnRebuildDirtyWidget = (e, _) => builds++;
    final frames = <double>[];
    for (var i = 0; i < 40; i++) {
      await tester.drag(mainList(), const Offset(0, -250));
      final sw = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 16));
      frames.add(sw.elapsedMicroseconds / 1000);
    }
    debugOnRebuildDirtyWidget = null;
    frames.sort();
    return (frames, builds / frames.length);
  }

  double p95(List<double> xs) => xs[((xs.length - 1) * .95).round()];

  // Debug-mode frame time on the CI machine: only catches gross regressions.
  const budgetMs = 60.0;

  testWidgets('chapter 18 (78 verses)', (tester) async {
    final (f, perFrame) = await scrollFrames(tester, '/chapters/18');
    // ignore: avoid_print
    print(
      'BENCH chapter 18 list: frame p95 ${p95(f).toStringAsFixed(1)} ms (debug), ${perFrame.toStringAsFixed(0)} widgets rebuilt per frame',
    );
    // Only rows scrolling into view are built (measured ~55).
    expect(perFrame, lessThan(110));
    expect(p95(f), lessThan(budgetMs));
  });

  testWidgets('reader, largest text size', (tester) async {
    final (f, perFrame) = await scrollFrames(tester, '/verse/2.47', textScale: AppSettings.maxTextScale);
    // ignore: avoid_print
    print(
      'BENCH reader at max text size: frame p95 ${p95(f).toStringAsFixed(1)} ms (debug), ${perFrame.toStringAsFixed(0)} widgets rebuilt per frame',
    );
    // Only rows scrolling into view are built (measured ~22).
    expect(perFrame, lessThan(45));
    expect(p95(f), lessThan(budgetMs));
  });

  testWidgets('search results for a question', (tester) async {
    final (f, perFrame) = await scrollFrames(tester, '/search', type: 'How do I control my anger?');
    // ignore: avoid_print
    print(
      'BENCH search results: frame p95 ${p95(f).toStringAsFixed(1)} ms (debug), ${perFrame.toStringAsFixed(0)} widgets rebuilt per frame',
    );
    // Only rows scrolling into view are built (measured ~40).
    expect(perFrame, lessThan(80));
    expect(p95(f), lessThan(budgetMs));
  });
}
