import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/content/models.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/lotus.dart';
import '../../shared/verse_text_view.dart';

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
            _SectionLabel(l.continueLearning),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                title: Text(l.beginWithChapter(1)),
                subtitle: Text('${first.nameIn(settings.verseScript)} · ${l.verseCount(first.verseCount)}'),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () => context.push('/chapters/1'),
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
            const SizedBox(height: 28),
            _SectionLabel(l.comingNext),
            _ComingNext(
              items: [l.featureListen, l.featureTeacher, l.featureSearch, l.featureMyGita, l.featureDaily],
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

class _ComingNext extends StatelessWidget {
  const _ComingNext({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.radio_button_unchecked, size: 14, color: muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item, style: TextStyle(color: muted)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
