import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio/manifest.dart';
import '../../core/audio/tts_provider.dart';
import '../../l10n/app_localizations.dart';

final _voicesProvider = FutureProvider<List<Voice>>((ref) async {
  final all = <Voice>[];
  for (final p in ref.watch(ttsProvidersProvider)) {
    all.addAll(await p.getVoices());
  }
  return all;
});

/// Settings section: pick the voice for English, Telugu and Sanskrit
/// (Sanskrit lists Sanskrit voices and, as an approximation, Hindi ones).
class VoiceSettingsSection extends ConsumerWidget {
  const VoiceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final voices = ref.watch(_voicesProvider);
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    return voices.when(
      loading: () => const Padding(padding: EdgeInsets.all(20), child: LinearProgressIndicator()),
      error: (_, _) => ListTile(title: Text(l.noVoicesFound)),
      data: (all) {
        if (all.isEmpty) return ListTile(title: Text(l.noVoicesFound));
        final rows = {
          'en': (l.languageEnglish, all.where((v) => v.language == 'en')),
          'te': (l.languageTelugu, all.where((v) => v.language == 'te')),
          'sa': (l.languageSanskrit, all.where((v) => v.language == 'sa' || v.language == 'hi')),
        };
        final sample = ref.watch(contentRepositoryProvider).verse('2.47')?.sanskrit.split('\n').first ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final MapEntry(key: lang, value: (name, options)) in rows.entries)
              ListTile(
                title: Text(l.voiceFor(name)),
                subtitle: options.isEmpty
                    ? Text(l.noVoice(name))
                    : DropdownButton<String>(
                        isExpanded: true,
                        value: options.any((v) => v.id == settings.voicePrefs[lang])
                            ? settings.voicePrefs[lang]
                            : '',
                        items: [
                          DropdownMenuItem(value: '', child: Text(l.voiceAutomatic)),
                          for (final v in options)
                            DropdownMenuItem(
                              value: v.id,
                              child: Text('${v.name} (${v.locale})', overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (id) => ref
                            .read(settingsProvider.notifier)
                            .update(
                              (s) => s.copyWith(
                                voicePrefs: {...s.voicePrefs}
                                  ..removeWhere((k, _) => k == lang)
                                  ..addAll({if (id != null && id.isNotEmpty) lang: id}),
                              ),
                            ),
                      ),
                trailing: options.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l.preview,
                        icon: const Icon(Icons.play_circle_outline),
                        onPressed: () => ref
                            .read(playbackControllerProvider)
                            .open(
                              previewManifest(lang, lang == 'sa' ? sample : l.previewSentence),
                              resume: false,
                            ),
                      ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(l.voiceSanskritNote, style: theme.textTheme.bodySmall),
            ),
          ],
        );
      },
    );
  }
}
