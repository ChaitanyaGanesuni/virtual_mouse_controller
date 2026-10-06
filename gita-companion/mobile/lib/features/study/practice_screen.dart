import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/content/models.dart';
import '../../core/study/study_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/provenance.dart';
import '../../shared/verse_text_view.dart';
import '../audio/listen_actions.dart';

final _practiceProvider = StreamProvider.family<DayPractice?, String>(
  (ref, date) => ref.watch(studyRepositoryProvider).watchPractice(date),
);

/// Daily Practice with today's verse: listen → understand → reflect →
/// apply → journal. Steps are ticked off by the user; there are no streaks
/// and nothing is lost by missing a day.
class PracticeScreen extends ConsumerStatefulWidget {
  const PracticeScreen({super.key});

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  final _journal = TextEditingController();
  var _loadedJournal = false;

  @override
  void dispose() {
    _journal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final repo = ref.watch(contentRepositoryProvider);
    final settings = ref.watch(settingsProvider);
    final study = ref.watch(studyRepositoryProvider);
    final now = ref.watch(clockProvider)();
    final date = StudyRepository.dateKey(now);
    final verse = repo.verseOfTheDay(now);
    final day = ref.watch(_practiceProvider(date)).value;
    if (!_loadedJournal && ref.watch(_practiceProvider(date)).hasValue) {
      _loadedJournal = true;
      _journal.text = day?.journal ?? '';
    }

    final translation = pickText(
      verse.textsOfKind('translation'),
      language: settings.translationLanguage,
      languageOf: (t) => t.language,
      statusOf: (t) => t.reviewStatus,
      isAi: (t) => repo.source(t.sourceId)?.kind == 'ai',
    );
    final simple = pickText(
      verse.textsOfKind('simple'),
      language: settings.explanationLanguage,
      languageOf: (t) => t.language,
      statusOf: (t) => t.reviewStatus,
      isAi: (t) => repo.source(t.sourceId)?.kind == 'ai',
    );

    Widget step({
      required int n,
      required String title,
      required PracticeStep? kind,
      required bool done,
      required List<Widget> children,
    }) => Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  done ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: done ? theme.colorScheme.primary : theme.colorScheme.outline,
                  semanticLabel: done ? l.stepDone : l.stepNotDone,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('$n. $title', style: theme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
            if (kind != null && !done)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => study.completeStep(date, verse.id, kind),
                  child: Text(l.markDone),
                ),
              ),
          ],
        ),
      ),
    );

    final steps = [day?.listenedAt, day?.understoodAt, day?.reflectedAt, day?.appliedAt];
    final completed = steps.where((s) => s != null).length;

    return Scaffold(
      appBar: AppBar(title: Text(l.dailyPractice)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              completed == 4 ? l.practiceComplete : l.practiceSteps(completed, 4),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          step(
            n: 1,
            title: l.stepListen,
            kind: PracticeStep.listen,
            done: day?.listenedAt != null,
            children: [
              VerseTextView(verse: verse, compact: true),
              const SizedBox(height: 8),
              VerseListenActions(verse: verse, explanation: simple),
            ],
          ),
          step(
            n: 2,
            title: l.stepUnderstand,
            kind: PracticeStep.understand,
            done: day?.understoodAt != null,
            children: [
              if (translation != null) ...[
                Text(translation.body, style: theme.textTheme.bodyLarge?.copyWith(height: 1.6)),
                ProvenanceNote(sourceId: translation.sourceId, reviewStatus: translation.reviewStatus),
              ],
              if (simple != null) ...[
                const SizedBox(height: 8),
                Text(simple.body),
                ProvenanceNote(sourceId: simple.sourceId, reviewStatus: simple.reviewStatus),
              ],
              TextButton(onPressed: () => context.push('/verse/${verse.id}'), child: Text(l.openInReader)),
            ],
          ),
          step(
            n: 3,
            title: l.stepReflect,
            kind: PracticeStep.reflect,
            done: day?.reflectedAt != null,
            children: [Text(l.reflectPrompt)],
          ),
          step(
            n: 4,
            title: l.stepApply,
            kind: PracticeStep.apply,
            done: day?.appliedAt != null,
            children: [Text(l.applyPrompt)],
          ),
          step(
            n: 5,
            title: l.stepJournal,
            kind: null,
            done: (day?.journal ?? '').isNotEmpty,
            children: [
              TextField(
                controller: _journal,
                minLines: 3,
                maxLines: 10,
                maxLength: 20000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: l.journalHint, border: const OutlineInputBorder()),
              ),
              Text(l.journalPrivacy, style: theme.textTheme.bodySmall),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () async {
                    await study.saveJournal(date, verse.id, _journal.text.trim());
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.journalSaved)));
                    }
                  },
                  child: Text(l.save),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
