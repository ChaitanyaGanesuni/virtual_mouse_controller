import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/content/models.dart';
import '../../l10n/app_localizations.dart';
import '../audio/voice_settings.dart';
import '../../shared/verse_text_view.dart';
import '../study/sync_settings.dart';
import '../tutor/teacher_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final sample = ref.watch(contentRepositoryProvider).verse('2.47');

    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _Header(l.appearance),
          _Padded(
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text(l.themeSystem)),
                ButtonSegment(value: ThemeMode.light, label: Text(l.themeLight)),
                ButtonSegment(value: ThemeMode.dark, label: Text(l.themeDark)),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => ctrl.update((x) => x.copyWith(themeMode: v.first)),
            ),
          ),
          ListTile(title: Text(l.textSize)),
          Slider(
            value: s.textScale,
            min: 0.85,
            max: 1.6,
            divisions: 15,
            label: '${(s.textScale * 100).round()}%',
            onChanged: (v) => ctrl.update((x) => x.copyWith(textScale: v)),
          ),
          if (sample != null)
            _Padded(
              child: VerseTextView(verse: sample, textAlign: TextAlign.start),
            ),
          const Divider(height: 32),
          _Header(l.languages),
          _Choice<String>(
            title: l.appLanguage,
            value: s.uiLanguage,
            options: {'en': l.languageEnglish, 'te': l.languageTelugu},
            onChanged: (v) => ctrl.update((x) => x.copyWith(uiLanguage: v)),
          ),
          _Choice<VerseScript>(
            title: l.verseScript,
            value: s.verseScript,
            options: {
              VerseScript.devanagari: l.scriptDevanagari,
              VerseScript.telugu: l.scriptTelugu,
              VerseScript.iast: l.scriptIast,
            },
            onChanged: (v) => ctrl.update((x) => x.copyWith(verseScript: v)),
          ),
          SwitchListTile(
            title: Text(l.showTransliteration),
            value: s.showTransliteration,
            onChanged: s.verseScript == VerseScript.iast
                ? null
                : (v) => ctrl.update((x) => x.copyWith(showTransliteration: v)),
          ),
          _Choice<String>(
            title: l.translationLanguage,
            value: s.translationLanguage,
            options: {'en': l.languageEnglish, 'te': l.languageTelugu},
            onChanged: (v) => ctrl.update((x) => x.copyWith(translationLanguage: v)),
          ),
          _Choice<String>(
            title: l.explanationLanguage,
            value: s.explanationLanguage,
            options: {'en': l.languageEnglish, 'te': l.languageTelugu},
            onChanged: (v) => ctrl.update((x) => x.copyWith(explanationLanguage: v)),
          ),
          const Divider(height: 32),
          _Header(l.voices),
          const VoiceSettingsSection(),
          _Header(l.settingsTeacher),
          const TeacherSettingsSection(),
          _Header(l.settingsSync),
          const SyncSettingsSection(),
          ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: Text(l.downloads),
            subtitle: Text(l.downloadsHint),
            onTap: () => context.push('/settings/downloads'),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(l.sourcesAndLicences),
            onTap: () => context.push('/settings/sources'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(l.openSourceLicences),
            onTap: () => showLicensePage(context: context, applicationName: l.appTitle),
          ),
        ],
      ),
    );
  }
}

class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final sources = ref.watch(contentRepositoryProvider).sources();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.sourcesAndLicences)),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: sources.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (context, i) {
          final src = sources[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(src.title, style: theme.textTheme.titleMedium),
              Text(src.author, style: theme.textTheme.bodyMedium),
              Text(
                [src.license, if (src.isAiGenerated) l.aiLabel, if (src.url != null) src.url!].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    ),
  );
}

class _Padded extends StatelessWidget {
  const _Padded({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), child: child);
}

class _Choice<T> extends StatelessWidget {
  const _Choice({required this.title, required this.value, required this.options, required this.onChanged});

  final String title;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in options.entries)
            ChoiceChip(label: Text(e.value), selected: e.key == value, onSelected: (_) => onChanged(e.key)),
        ],
      ),
    ),
  );
}
