import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/content/estimates.dart';
import '../../core/content/models.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/provenance.dart';
import '../../core/packs/download_manager.dart';
import '../audio/listen_actions.dart';

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
    final estimate = estimateChapter(verses, explanationLanguage: settings.explanationLanguage);

    ChapterText? pick(String kind) => pickText(
      chapter.texts.where((t) => t.kind == kind).toList(),
      language: settings.explanationLanguage,
      languageOf: (t) => t.language,
      statusOf: (t) => t.reviewStatus,
      isAi: (t) => repo.source(t.sourceId)?.kind == 'ai',
    );
    final themeText = pick('theme');
    final summary = pick('summary');
    const titleNote = ProvenanceNote(
      sourceId: 'gita-companion-editorial',
      reviewStatus: ReviewStatus.unreviewed,
    );
    final sharedSource = [themeText, summary].every(
      (t) => t == null || (t.sourceId == titleNote.sourceId && t.reviewStatus == titleNote.reviewStatus),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l.chapterNumber(number)),
        actions: [_OfflineButton(chapter: number)],
      ),
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
                  const SizedBox(height: 4),
                  Text(chapter.titleEn, style: theme.textTheme.bodyMedium),
                  if (!sharedSource) titleNote,
                  if (themeText != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      l.centralTheme,
                      style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 4),
                    Text(themeText.body, style: theme.textTheme.titleMedium?.copyWith(height: 1.4)),
                    if (!sharedSource)
                      ProvenanceNote(sourceId: themeText.sourceId, reviewStatus: themeText.reviewStatus),
                  ],
                  if (summary != null) ...[
                    const SizedBox(height: 16),
                    _ExpandableSummary(text: summary, showSource: !sharedSource),
                  ],
                  // One label when the title gloss, theme and summary share a source.
                  if (sharedSource) titleNote,
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      _Stat(icon: Icons.format_list_numbered, text: l.verseCount(chapter.verseCount)),
                      _Stat(
                        icon: Icons.menu_book_outlined,
                        text: l.aboutMinutesRead(estimate.readingMinutes),
                      ),
                      _Stat(
                        icon: Icons.headphones_outlined,
                        text: l.aboutMinutesListen(estimate.listeningMinutes),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => context.push('/verse/${verses.first.id}'),
                          icon: const Icon(Icons.menu_book),
                          label: Text(l.startReading),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => startListening(
                            context,
                            ref,
                            ref.read(manifestResolverProvider).chapter(number, settings.explanationLanguage),
                          ),
                          icon: const Icon(Icons.headphones),
                          label: Text(l.startListening),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: muted),
        const SizedBox(width: 6),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ExpandableSummary extends StatefulWidget {
  const _ExpandableSummary({required this.text, required this.showSource});

  final ChapterText text;
  final bool showSource;

  @override
  State<_ExpandableSummary> createState() => _ExpandableSummaryState();
}

class _ExpandableSummaryState extends State<_ExpandableSummary> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.summary, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
        const SizedBox(height: 4),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: Text(
            widget.text.body,
            maxLines: _open ? null : 4,
            overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: widget.showSource
                  ? ProvenanceNote(sourceId: widget.text.sourceId, reviewStatus: widget.text.reviewStatus)
                  : const SizedBox.shrink(),
            ),
            TextButton(
              onPressed: () => setState(() => _open = !_open),
              child: Text(_open ? l.showLess : l.readMore),
            ),
          ],
        ),
      ],
    );
  }
}

/// Makes the chapter's audio available offline, or shows that it is.
class _OfflineButton extends ConsumerWidget {
  const _OfflineButton({required this.chapter});

  final int chapter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final language = ref.watch(settingsProvider).explanationLanguage;
    final status = ref.watch(downloadsOverviewProvider(language)).value?.audio[chapter];
    return switch (status?.state) {
      PackState.downloaded => IconButton(
        tooltip: l.availableOfflineShort,
        icon: const Icon(Icons.offline_pin),
        onPressed: () => context.push('/settings/downloads'),
      ),
      PackState.queued || PackState.downloading => IconButton(
        tooltip: l.preparingProgress(status!.done, status.total),
        icon: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2.5, value: status.progress),
        ),
        onPressed: () => context.push('/settings/downloads'),
      ),
      _ => IconButton(
        tooltip: l.makeAvailableOffline,
        icon: const Icon(Icons.download_for_offline_outlined),
        onPressed: () {
          ref.read(downloadManagerProvider).downloadAudio(chapter, language);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.preparingChapter(chapter))));
        },
      ),
    };
  }
}
