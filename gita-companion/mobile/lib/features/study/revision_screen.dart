import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/content/models.dart';
import '../../core/study/srs.dart';
import '../../core/study/study_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/provenance.dart';
import '../../shared/verse_text_view.dart';

/// A revision session: today's due cards, one at a time. The user recalls,
/// reveals the verse's meaning, and grades honestly (Again / Hard / Good /
/// Easy). "Again" brings the card back at the end of the session.
class RevisionScreen extends ConsumerStatefulWidget {
  const RevisionScreen({super.key});

  @override
  ConsumerState<RevisionScreen> createState() => _RevisionScreenState();
}

class _RevisionScreenState extends ConsumerState<RevisionScreen> {
  List<RevisionCard>? _queue;
  var _revealed = false;
  var _done = 0;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(studyRepositoryProvider).dueCards().then((cards) {
      if (mounted) setState(() => _queue = cards);
    });
  }

  Future<void> _rate(RevisionCard card, Rating rating) async {
    if (_busy) return;
    setState(() => _busy = true);
    final repo = ref.read(studyRepositoryProvider);
    await repo.review(card, rating);
    RevisionCard? again;
    if (rating == Rating.again) {
      again = await repo.card(card.verseId, card.cardType);
    }
    if (!mounted) return;
    setState(() {
      _queue = [..._queue!.skip(1), ?again];
      _revealed = false;
      _busy = false;
      if (rating != Rating.again) _done++;
    });
  }

  String _wait(AppLocalizations l, Duration d) =>
      d.inHours < 24 ? l.inMinutes(d.inMinutes) : l.inDays((d.inHours / 24).round());

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final queue = _queue;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.revision),
        actions: [
          if (queue != null && queue.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(l.cardsLeft(queue.length), style: theme.textTheme.bodySmall),
              ),
            ),
        ],
      ),
      body: queue == null
          ? const Center(child: CircularProgressIndicator())
          : queue.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _done > 0 ? l.revisionFinished(_done) : l.revisionNothingDue,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(onPressed: () => context.pop(), child: Text(l.back)),
                ],
              ),
            )
          : _Card(
              card: queue.first,
              revealed: _revealed,
              onReveal: () => setState(() => _revealed = true),
              buttons: [
                for (final r in Rating.values)
                  _RateButton(
                    label: switch (r) {
                      Rating.again => l.rateAgain,
                      Rating.hard => l.rateHard,
                      Rating.good => l.rateGood,
                      Rating.easy => l.rateEasy,
                    },
                    wait: _wait(
                      l,
                      ref
                          .read(studyRepositoryProvider)
                          .scheduler
                          .preview(
                            ref.read(studyRepositoryProvider).scheduleOf(queue.first),
                            r,
                            ref.read(clockProvider)().toUtc(),
                          ),
                    ),
                    primary: r == Rating.good,
                    onPressed: _busy ? null : () => _rate(queue.first, r),
                  ),
              ],
            ),
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.card, required this.revealed, required this.onReveal, required this.buttons});

  final RevisionCard card;
  final bool revealed;
  final VoidCallback onReveal;
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final repo = ref.watch(contentRepositoryProvider);
    final settings = ref.watch(settingsProvider);
    final verse = repo.verse(card.verseId)!;
    final type = CardType.fromWire(card.cardType);
    final translation = pickText(
      verse.textsOfKind('translation'),
      language: settings.translationLanguage,
      languageOf: (t) => t.language,
      statusOf: (t) => t.reviewStatus,
      isAi: (t) => repo.source(t.sourceId)?.kind == 'ai',
    );
    final practical = pickText(
      verse.textsOfKind(type == CardType.application ? 'practical' : 'simple'),
      language: settings.explanationLanguage,
      languageOf: (t) => t.language,
      statusOf: (t) => t.reviewStatus,
      isAi: (t) => repo.source(t.sourceId)?.kind == 'ai',
    );
    final topics =
        ref.read(searchServiceProvider).topics().where((c) => c.verses.containsKey(verse.id)).toList()
          ..sort((a, b) => b.verses[verse.id]!.compareTo(a.verses[verse.id]!));

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        Text(
          l.verseRef(verse.id),
          style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 12),
        VerseTextView(verse: verse, compact: true),
        const SizedBox(height: 24),
        Text(switch (type) {
          CardType.meaning => l.promptMeaning,
          CardType.concept => l.promptConcept,
          CardType.application => l.promptApplication,
        }, style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        if (!revealed)
          FilledButton.tonal(onPressed: onReveal, child: Text(l.showAnswer))
        else ...[
          if (translation != null) ...[
            Text(translation.body, style: theme.textTheme.bodyLarge?.copyWith(height: 1.6)),
            ProvenanceNote(sourceId: translation.sourceId, reviewStatus: translation.reviewStatus),
          ],
          if (practical != null) ...[
            const SizedBox(height: 12),
            Text(practical.body, style: theme.textTheme.bodyMedium),
            ProvenanceNote(sourceId: practical.sourceId, reviewStatus: practical.reviewStatus),
          ],
          if (topics.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in topics.take(3))
                  Chip(
                    label: Text(
                      c.termSa.isEmpty
                          ? c.name(settings.uiLanguage)
                          : '${c.name(settings.uiLanguage)} (${c.termSa})',
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text(l.howWellRemembered, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          for (var i = 0; i < buttons.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [for (final b in buttons.skip(i).take(2)) Expanded(child: b)]),
            ),
        ],
      ],
    );
  }
}

class _RateButton extends StatelessWidget {
  const _RateButton({required this.label, required this.wait, required this.onPressed, this.primary = false});

  final String label;
  final String wait;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          Text(wait, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: null)),
        ],
      ),
    );
    final style = ButtonStyle(
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: primary
          ? FilledButton(style: style, onPressed: onPressed, child: child)
          : OutlinedButton(style: style, onPressed: onPressed, child: child),
    );
  }
}
