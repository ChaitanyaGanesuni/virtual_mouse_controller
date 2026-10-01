import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/content/content_repository.dart';
import '../core/search/search_service.dart';
import '../core/settings/app_settings.dart';

/// Composition root. Real implementations are supplied in main.dart via
/// ProviderScope overrides; tests supply fakes the same way.
final contentRepositoryProvider = Provider<ContentRepository>(
  (ref) => throw UnimplementedError('contentRepositoryProvider must be overridden'),
);

final searchServiceProvider = Provider<SearchService>(
  (ref) => throw UnimplementedError('searchServiceProvider must be overridden'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => throw UnimplementedError('settingsRepositoryProvider must be overridden'),
);

/// Settings loaded at startup, before the first frame.
final initialSettingsProvider = Provider<AppSettings>((ref) => const AppSettings());

/// Clock, overridable in tests (Today's verse depends on the date).
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  Future<void> update(AppSettings Function(AppSettings) change) async {
    final next = change(state);
    if (next == state) return;
    state = next;
    await ref.read(settingsRepositoryProvider).save(next);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
