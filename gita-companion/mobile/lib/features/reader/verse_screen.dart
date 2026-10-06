import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/content/models.dart';
import '../../core/settings/app_settings.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/provenance.dart';
import '../../shared/verse_text_view.dart';
import '../audio/listen_actions.dart';
import '../study/study_widgets.dart';

/// The selected explanation mode stays the same while swiping between verses.
class ExplanationModeController extends Notifier<ExplanationMode> {
  @override
  ExplanationMode build() => ExplanationMode.simple;

  void select(ExplanationMode mode) => state = mode;
}

final explanationModeProvider = NotifierProvider<ExplanationModeController, ExplanationMode>(
  ExplanationModeController.new,
);

/// Verse reader: swipe through all verses in reading order (across chapters).
class VerseScreen extends ConsumerStatefulWidget {
  const VerseScreen({super.key, required this.verseId});

  final String verseId;

  @override
  ConsumerState<VerseScreen> createState() => _VerseScreenState();
}

class _VerseScreenState extends ConsumerState<VerseScreen> {
  late final List<String> _order;
  late final PageController _pages;
  late int _index;

  @override
  void initState() {
    super.initState();
    _order = ref.read(contentRepositoryProvider).readingOrder();
    _index = _order.indexOf(widget.verseId).clamp(0, _order.length - 1);
    _pages = PageController(initialPage: _index);
    _markRead(_order[_index]);
  }

  // Opening a verse counts as reading it ("Chapter 2 · 14 of 72 verses").
  void _markRead(String id) => ref.read(studyRepositoryProvider).markRead(id);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int delta) => _pages.animateToPage(
    _index + delta,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final repo = ref.watch(contentRepositoryProvider);
    final settings = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final id = _order[_index];
    final verse = repo.verse(id)!;
    final inChapter = repo.versesOf(verse.chapter).map((v) => v.id).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.verseRef(verse.id)),
            Text(
              l.chapterPosition(verse.chapter, inChapter.indexOf(id) + 1, inChapter.length),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l.textSmaller,
            icon: const Icon(Icons.text_decrease),
            onPressed: settings.textScale <= AppSettings.minTextScale
                ? null
                : () => ctrl.update((s) => s.copyWith(textScale: s.textScale - 0.1)),
          ),
          IconButton(
            tooltip: l.textLarger,
            icon: const Icon(Icons.text_increase),
            onPressed: settings.textScale >= AppSettings.maxTextScale
                ? null
                : () => ctrl.update((s) => s.copyWith(textScale: s.textScale + 0.1)),
          ),
          PopupMenuButton<VerseScript>(
            tooltip: l.script,
            icon: const Icon(Icons.translate),
            initialValue: settings.verseScript,
            onSelected: (v) => ctrl.update((s) => s.copyWith(verseScript: v)),
            itemBuilder: (_) => [
              PopupMenuItem(value: VerseScript.devanagari, child: Text(l.scriptDevanagari)),
              PopupMenuItem(value: VerseScript.telugu, child: Text(l.scriptTelugu)),
              PopupMenuItem(value: VerseScript.iast, child: Text(l.scriptIast)),
            ],
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: _order.length,
        onPageChanged: (i) {
          setState(() => _index = i);
          _markRead(_order[i]);
        },
        itemBuilder: (context, i) => _VersePage(verseId: _order[i]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _index == 0 ? null : () => _go(-1),
                icon: const Icon(Icons.chevron_left),
                label: Text(l.previousVerse),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _index == _order.length - 1 ? null : () => _go(1),
                icon: const Icon(Icons.chevron_right),
                label: Text(l.nextVerse),
                iconAlignment: IconAlignment.end,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VersePage extends ConsumerWidget {
  const _VersePage({required this.verseId});

  final String verseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final repo = ref.watch(contentRepositoryProvider);
    final settings = ref.watch(settingsProvider);
    final verse = repo.verse(verseId)!;
    final theme = Theme.of(context);

    final translation = pickText(
      verse.textsOfKind('translation'),
      language: settings.translationLanguage,
      languageOf: (t) => t.language,
      statusOf: (t) => t.reviewStatus,
      isAi: (t) => repo.source(t.sourceId)?.kind == 'ai',
    );
    final wordLanguage = verse.wordMeanings.any((w) => w.language == settings.explanationLanguage)
        ? settings.explanationLanguage
        : verse.wordMeanings.firstOrNull?.language;
    final words = verse.wordMeanings.where((w) => w.language == wordLanguage).toList();
    final mode = ref.watch(explanationModeProvider);
    final shownExplanation = pickText(
      verse.textsOfKind(mode.kind),
      language: settings.explanationLanguage,
      languageOf: (t) => t.language,
      statusOf: (t) => t.reviewStatus,
      isAi: (t) => repo.source(t.sourceId)?.kind == 'ai',
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        VerseTextView(verse: verse),
        const SizedBox(height: 12),
        ProvenanceNote(
          sourceId: verse.sourceId,
          reviewStatus: verse.reviewStatus,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        VerseListenActions(verse: verse, explanation: shownExplanation),
        StudyBar(verseId: verse.id),
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: Text(l.askAboutVerse),
            onPressed: () => context.push('/tutor?verse=${verse.id}'),
          ),
        ),
        if (!verse.isCanonical) ...[
          const SizedBox(height: 16),
          Notice(text: l.nonCanonicalNote, icon: Icons.info_outline),
        ],
        if (words.isNotEmpty) ...[
          _Heading(l.wordByWord),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in words)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: w.word,
                          style: const TextStyle(
                            fontFamily: 'NotoSerif',
                            fontFamilyFallback: ['NotoSerifDevanagari'],
                          ),
                        ),
                        TextSpan(text: '  ${w.meaning}', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          ProvenanceNote(sourceId: words.first.sourceId, reviewStatus: ReviewStatus.unreviewed),
        ],
        _Heading(l.translation),
        if (translation == null)
          Notice(text: l.translationPending, icon: Icons.translate)
        else ...[
          HighlightableText(
            text: translation.body,
            verseId: verse.id,
            textId: translation.id,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
          ),
          ProvenanceNote(sourceId: translation.sourceId, reviewStatus: translation.reviewStatus),
        ],
        VerseNotes(verseId: verse.id),
        _Heading(l.understand),
        _ExplanationCard(verse: verse),
      ],
    );
  }
}

class _ExplanationCard extends ConsumerWidget {
  const _ExplanationCard({required this.verse});

  final Verse verse;

  static const _languages = ['en', 'te'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final repo = ref.watch(contentRepositoryProvider);
    final settings = ref.watch(settingsProvider);
    final mode = ref.watch(explanationModeProvider);
    final theme = Theme.of(context);
    final language = settings.explanationLanguage;

    String langName(String code) => code == 'te' ? l.languageTelugu : l.languageEnglish;
    String modeName(ExplanationMode m) => switch (m) {
      ExplanationMode.simple => l.modeSimple,
      ExplanationMode.deep => l.modeDeep,
      ExplanationMode.practical => l.modePractical,
      ExplanationMode.story => l.modeStory,
      ExplanationMode.child => l.modeChild,
      ExplanationMode.sanskritTerms => l.modeTerms,
    };

    final anyExplanation = ExplanationMode.values.any((m) => verse.textsOfKind(m.kind).isNotEmpty);
    final text = pickText(
      verse.textsOfKind(mode.kind),
      language: language,
      languageOf: (t) => t.language,
      statusOf: (t) => t.reviewStatus,
      isAi: (t) => repo.source(t.sourceId)?.kind == 'ai',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final m in ExplanationMode.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(modeName(m)),
                    selected: m == mode,
                    onSelected: (_) => ref.read(explanationModeProvider.notifier).select(m),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [for (final c in _languages) ButtonSegment(value: c, label: Text(langName(c)))],
          selected: {language},
          onSelectionChanged: (v) =>
              ref.read(settingsProvider.notifier).update((s) => s.copyWith(explanationLanguage: v.first)),
        ),
        const SizedBox(height: 14),
        if (!anyExplanation || text == null) ...[
          Notice(text: l.explanationsNotYet, icon: Icons.hourglass_empty),
          const SizedBox(height: 8),
          // Generated on demand by the AI teacher, with checked sources.
          OutlinedButton.icon(
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: Text(l.explainWithTeacher),
            onPressed: () => context.push('/tutor?verse=${verse.id}&explain=${mode.kind}'),
          ),
        ] else ...[
          if (text.language != language)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l.shownInOtherLanguage(langName(language), langName(text.language)),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
          if (mode == ExplanationMode.sanskritTerms)
            ..._terms(context, text.body)
          else
            Text(text.body, style: theme.textTheme.bodyLarge?.copyWith(height: 1.65)),
          Row(
            children: [
              Expanded(
                child: ProvenanceNote(sourceId: text.sourceId, reviewStatus: text.reviewStatus),
              ),
              ReadExplanationButton(verse: verse, text: text),
            ],
          ),
        ],
      ],
    );
  }

  List<Widget> _terms(BuildContext context, String body) {
    final theme = Theme.of(context);
    List<dynamic> items;
    try {
      items = jsonDecode(body) as List<dynamic>;
    } on FormatException {
      return [Text(body)];
    }
    return [
      for (final item in items.cast<Map<String, dynamic>>())
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['term'] as String,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFamily: 'NotoSerif',
                  color: theme.colorScheme.primary,
                ),
              ),
              Text(item['meaning'] as String, style: theme.textTheme.bodyMedium?.copyWith(height: 1.55)),
            ],
          ),
        ),
    ];
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 10),
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

class Notice extends StatelessWidget {
  const Notice({super.key, required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
