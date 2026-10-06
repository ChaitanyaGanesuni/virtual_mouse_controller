import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/content/models.dart';
import '../../core/study/study_repository.dart';
import '../../l10n/app_localizations.dart';
import 'study_widgets.dart';

final _bookmarksProvider = StreamProvider<List<Bookmark>>(
  (ref) => ref.watch(studyRepositoryProvider).watchBookmarks(),
);
final _favoritesProvider = StreamProvider<List<String>>(
  (ref) => ref.watch(studyRepositoryProvider).watchFavorites(),
);
final _notesProvider = StreamProvider<List<StudyNote>>(
  (ref) => ref.watch(studyRepositoryProvider).watchNotes(),
);
final _highlightsProvider = StreamProvider<List<StudyHighlight>>(
  (ref) => ref.watch(studyRepositoryProvider).watchHighlights(),
);
final _journalProvider = StreamProvider<List<DayPractice>>(
  (ref) => ref.watch(studyRepositoryProvider).watchJournal(),
);

/// "My Gita": progress and revision, saved verses, notes and the journal,
/// highlights. Everything here lives on the device (and syncs only if the
/// user turns sync on).
class MyGitaScreen extends StatelessWidget {
  const MyGitaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.myGita),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: l.myGitaOverview),
              Tab(text: l.myGitaSaved),
              Tab(text: l.myGitaNotes),
              Tab(text: l.myGitaHighlights),
            ],
          ),
        ),
        body: const TabBarView(children: [_Overview(), _Saved(), _Notes(), _Highlights()]),
      ),
    );
  }
}

class _Overview extends ConsumerWidget {
  const _Overview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final repo = ref.watch(contentRepositoryProvider);
    final script = ref.watch(settingsProvider).verseScript;
    final progress = ref.watch(studyProgressProvider).value ?? const StudyProgress();
    final due = ref.watch(dueCountProvider).value ?? 0;
    final total = repo.chapters().fold(0, (n, c) => n + c.verseCount);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.revision, style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  due > 0
                      ? l.cardsDue(due)
                      : progress.cards == 0
                      ? l.revisionEmpty
                      : l.revisionNothingDue,
                  style: theme.textTheme.bodyMedium,
                ),
                if (due > 0) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.replay),
                    label: Text(l.startRevision),
                    onPressed: () => context.push('/my/revise'),
                  ),
                ],
              ],
            ),
          ),
        ),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: const Icon(Icons.self_improvement),
            title: Text(l.dailyPractice),
            subtitle: Text(l.dailyPracticeHint),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () => context.push('/practice'),
          ),
        ),
        const SizedBox(height: 16),
        Text(l.progress, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(l.versesReadOf(progress.versesRead, total)),
        Text(l.versesUnderstood(progress.understood)),
        if (progress.cards > 0) Text(l.cardsSettled(progress.cardsSettled, progress.cards)),
        const SizedBox(height: 12),
        for (final c in repo.chapters())
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: InkWell(
              onTap: () => context.push('/chapters/${c.number}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l.chapterNumber(c.number)} · ${c.nameIn(script)}',
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: (progress.readPerChapter[c.number] ?? 0) / c.verseCount,
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(2),
                          color: theme.colorScheme.primary,
                          backgroundColor: theme.colorScheme.outlineVariant,
                          semanticsLabel: l.chapterNumber(c.number),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        l.readOfVerses(progress.readPerChapter[c.number] ?? 0, c.verseCount),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _VerseTile extends ConsumerWidget {
  const _VerseTile({required this.verseId, this.trailing});

  final String verseId;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final verse = ref.watch(contentRepositoryProvider).verse(verseId);
    if (verse == null) return const SizedBox.shrink();
    final script = ref.watch(settingsProvider).verseScript;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(verse.textIn(script).split('\n').first, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(l.verseRef(verse.id)),
      trailing: trailing,
      onTap: () => context.push('/verse/$verseId'),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  );
}

class _Saved extends ConsumerWidget {
  const _Saved();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final bookmarks = ref.watch(_bookmarksProvider).value ?? const [];
    final favorites = ref.watch(_favoritesProvider).value ?? const [];
    final theme = Theme.of(context);
    if (bookmarks.isEmpty && favorites.isEmpty) return _Empty(l.savedEmpty);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (favorites.isNotEmpty) ...[
          Text(l.favorites, style: theme.textTheme.titleSmall),
          for (final v in favorites) _VerseTile(verseId: v, trailing: const Icon(Icons.favorite, size: 18)),
          const SizedBox(height: 16),
        ],
        if (bookmarks.isNotEmpty) ...[
          Text(l.bookmarks, style: theme.textTheme.titleSmall),
          for (final b in bookmarks)
            _VerseTile(verseId: b.verseId, trailing: const Icon(Icons.bookmark, size: 18)),
        ],
      ],
    );
  }
}

class _Notes extends ConsumerWidget {
  const _Notes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notes = ref.watch(_notesProvider).value ?? const [];
    final journal = ref.watch(_journalProvider).value ?? const [];
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.edit_note),
        label: Text(l.newNote),
        onPressed: () => showNoteEditor(context, ref),
      ),
      body: notes.isEmpty && journal.isEmpty
          ? _Empty(l.notesEmpty)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                for (final n in notes) NoteTile(note: n, showVerse: true),
                if (journal.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(l.journal, style: theme.textTheme.titleSmall),
                  for (final j in journal)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(j.journal, maxLines: 4, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${j.date} · ${l.verseRef(j.verseId)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

class _Highlights extends ConsumerWidget {
  const _Highlights();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final repo = ref.watch(contentRepositoryProvider);
    final highlights = ref.watch(_highlightsProvider).value ?? const [];
    if (highlights.isEmpty) return _Empty(l.highlightsEmpty);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        for (final h in highlights)
          Builder(
            builder: (context) {
              final verse = repo.verse(h.verseId);
              final VerseText? text = verse?.texts.where((t) => t.id == h.textId).firstOrNull;
              final body = text?.body ?? verse?.sanskrit ?? '';
              final excerpt = h.end <= body.length ? body.substring(h.start, h.end) : body;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Container(width: 6, height: 40, color: highlightColor(context, h.color)),
                title: Text('“$excerpt”', maxLines: 3, overflow: TextOverflow.ellipsis),
                subtitle: Text(l.verseRef(h.verseId)),
                onTap: () => context.push('/verse/${h.verseId}'),
                trailing: IconButton(
                  tooltip: l.removeHighlight,
                  icon: const Icon(Icons.close),
                  onPressed: () => ref.read(studyRepositoryProvider).deleteHighlight(h.id),
                ),
              );
            },
          ),
      ],
    );
  }
}
