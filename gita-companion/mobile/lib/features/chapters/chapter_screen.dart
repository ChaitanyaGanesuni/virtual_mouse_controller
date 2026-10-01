import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/content/models.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/provenance.dart';

/// Chapter overview and verse list. Summary, theme and reading/listening
/// times come in Phase 4 together with their (labelled) sources.
class ChapterScreen extends ConsumerWidget {
  const ChapterScreen({super.key, required this.number});

  final int number;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final repo = ref.watch(contentRepositoryProvider);
    final settings = ref.watch(settingsProvider);
    final chapter = repo.chapter(number);
    final verses = repo.versesOf(number);
    final theme = Theme.of(context);
    final script = settings.verseScript;

    return Scaffold(
      appBar: AppBar(title: Text(l.chapterNumber(number))),
      body: ListView.builder(
        itemCount: verses.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(chapter.nameIn(script), style: theme.textTheme.headlineSmall),
                  if (script != VerseScript.iast)
                    Text(chapter.nameIn(VerseScript.iast), style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(chapter.titleEn, style: theme.textTheme.bodyMedium),
                  const ProvenanceNote(
                    sourceId: 'gita-companion-editorial',
                    reviewStatus: ReviewStatus.unreviewed,
                  ),
                  const SizedBox(height: 12),
                  Text(l.verseCount(chapter.verseCount), style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  const Divider(),
                ],
              ),
            );
          }
          final v = verses[i - 1];
          final firstLine = v.textIn(script).split('\n').first;
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            leading: SizedBox(
              width: 44,
              child: Text(
                v.id,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: v.isCanonical ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            title: Text(firstLine, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => context.push('/verse/${v.id}'),
          );
        },
      ),
    );
  }
}
