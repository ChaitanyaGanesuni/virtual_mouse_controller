import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/content/models.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/lotus.dart';
import '../../shared/verse_text_view.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final sample = ref.watch(contentRepositoryProvider).verse('2.47');
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          children: [
            const Center(child: Lotus(size: 64)),
            const SizedBox(height: 20),
            Text(l.welcome, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(l.welcomeBody, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 28),
            Text(l.appLanguage, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'en', label: Text(l.languageEnglish)),
                ButtonSegment(value: 'te', label: Text(l.languageTelugu)),
              ],
              selected: {s.uiLanguage},
              onSelectionChanged: (v) => ctrl.update((x) => x.copyWith(uiLanguage: v.first)),
            ),
            const SizedBox(height: 24),
            Text(l.verseScript, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<VerseScript>(
              segments: [
                ButtonSegment(value: VerseScript.devanagari, label: Text(l.scriptDevanagari)),
                ButtonSegment(value: VerseScript.telugu, label: Text(l.scriptTelugu)),
                ButtonSegment(value: VerseScript.iast, label: Text(l.scriptIast)),
              ],
              selected: {s.verseScript},
              onSelectionChanged: (v) => ctrl.update((x) => x.copyWith(verseScript: v.first)),
            ),
            if (sample != null) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: VerseTextView(verse: sample),
                ),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () async {
                await ctrl.update((x) => x.copyWith(onboardingDone: true));
                if (context.mounted) context.go('/');
              },
              child: Text(l.begin),
            ),
          ],
        ),
      ),
    );
  }
}
