import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/chapters/chapter_screen.dart';
import '../features/chapters/chapters_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/reader/verse_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import 'providers.dart';

final _verseId = RegExp(r'^\d{1,2}\.\d{1,2}$');

final routerProvider = Provider<GoRouter>((ref) {
  final repo = ref.read(contentRepositoryProvider);
  return GoRouter(
    // Deep links such as gita://verse/2/47 map onto these paths.
    redirect: (context, state) {
      final done = ref.read(settingsProvider).onboardingDone;
      if (!done && state.matchedLocation != '/welcome') return '/welcome';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/chapters', builder: (_, _) => const ChaptersScreen()),
      GoRoute(
        path: '/chapters/:n',
        redirect: (_, state) {
          final n = int.tryParse(state.pathParameters['n']!);
          return (n == null || n < 1 || n > 18) ? '/chapters' : null;
        },
        builder: (_, state) => ChapterScreen(number: int.parse(state.pathParameters['n']!)),
      ),
      GoRoute(
        path: '/verse/:id',
        redirect: (_, state) {
          final id = state.pathParameters['id']!;
          return (_verseId.hasMatch(id) && repo.verse(id) != null) ? null : '/chapters';
        },
        builder: (_, state) => VerseScreen(verseId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/settings/sources', builder: (_, _) => const SourcesScreen()),
    ],
  );
});
