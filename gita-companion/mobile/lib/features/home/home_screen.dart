import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/content/models.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/lotus.dart';
import '../../shared/verse_text_view.dart';
import '../audio/continue_listening.dart';

const _titles = {
  VerseScript.devanagari: 'श्रीमद्भगवद्गीता',
  VerseScript.telugu: 'శ్రీమద్భగవద్గీతా',
  VerseScript.iast: 'Śrīmadbhagavadgītā',
};

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final repo = ref.watch(contentRepositoryProvider);
    final settings = ref.watch(settingsProvider);
    final today = repo.verseOfTheDay(ref.watch(clockProvider)());
    final first = repo.chapter(1);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Row(
              children: [
                const Lotus(size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _titles[settings.verseScript]!,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontFamily: switch (settings.verseScript) {
                            VerseScript.devanagari => 'NotoSerifDevanagari',
                            VerseScript.telugu => 'NotoSansTelugu',
                            VerseScript.iast => 'NotoSerif',
                          },
                        ),
                      ),
                      Text(l.appTitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: l.search,
                  icon: const Icon(Icons.search),
                  onPressed: () => context.push('/search'),
                ),
                IconButton(
                  tooltip: l.settings,
                  icon: const Icon(Icons.tune),
                  onPressed: () => context.push('/settings'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SectionLabel(l.todaysVerse),
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push('/verse/${today.id}'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Column(
                    children: [
                      VerseTextView(verse: today, compact: true),
                      const SizedBox(height: 12),
                      Text(
                        '${l.chapterNumber(today.chapter)} · ${l.verseRef(today.id)}',
                        style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.self_improvement),
                label: Text(l.dailyPractice),
                onPressed: () => context.push('/practice'),
              ),
            ),
            const SizedBox(height: 12),
            _SectionLabel(l.continueLearning),
            Card(
              child: Builder(
                builder: (context) {
                  final last = ref.watch(continueReadingProvider).value;
                  final next = last;
                  final verse = next == null ? null : repo.verse(next);
                  return verse == null
                      ? ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          title: Text(l.beginWithChapter(1)),
                          subtitle: Text(
                            '${first.nameIn(settings.verseScript)} · ${l.verseCount(first.verseCount)}',
                          ),
                          trailing: const Icon(Icons.arrow_forward),
                          onTap: () => context.push('/chapters/1'),
                        )
                      : ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          title: Text(l.continueAt(l.verseRef(verse.id))),
                          subtitle: Text(
                            '${l.chapterNumber(verse.chapter)} · ${repo.chapter(verse.chapter).nameIn(settings.verseScript)}',
                          ),
                          trailing: const Icon(Icons.arrow_forward),
                          onTap: () => context.push('/verse/${verse.id}'),
                        );
                },
              ),
            ),
            const SizedBox(height: 24),
            _SectionLabel(l.myGita),
            Card(
              child: Builder(
                builder: (context) {
                  final due = ref.watch(dueCountProvider).value ?? 0;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: const Icon(Icons.auto_stories_outlined),
                    title: Text(due > 0 ? l.cardsDue(due) : l.myGitaHomeTitle),
                    subtitle: Text(l.myGitaHomeHint),
                    trailing: const Icon(Icons.arrow_forward),
                    onTap: () => context.push(due > 0 ? '/my/revise' : '/my'),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            ContinueListeningCard(header: _SectionLabel(l.continueListening)),
            _SectionLabel(l.teacherTitle),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: const Icon(Icons.auto_awesome),
                title: Text(l.askTeacher),
                subtitle: Text(l.teacherHomeHint),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () => context.push('/tutor'),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: _SectionLabel(l.chapters)),
                TextButton(onPressed: () => context.push('/chapters'), child: Text(l.allChapters)),
              ],
            ),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: repo.chapters().length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final c = repo.chapters()[i];
                  return _ChapterChip(chapter: c, script: settings.verseScript);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, left: 4),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(letterSpacing: 1.2, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

class _ChapterChip extends StatelessWidget {
  const _ChapterChip({required this.chapter, required this.script});

  final Chapter chapter;
  final VerseScript script;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 150,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/chapters/${chapter.number}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${chapter.number}',
                  style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary),
                ),
                Text(
                  chapter.nameIn(script),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
