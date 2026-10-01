import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/provenance.dart';
import '../../shared/verse_text_view.dart';

/// Basic verse page (Phase 3). The full reader with translations, the
/// explanation modes, "Ask about this verse" and audio arrives in Phase 4+.
class VerseScreen extends ConsumerWidget {
  const VerseScreen({super.key, required this.verseId});

  final String verseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final repo = ref.watch(contentRepositoryProvider);
    final verse = repo.verse(verseId);
    final theme = Theme.of(context);

    if (verse == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l.verseRef(verseId))),
      );
    }
    final prev = repo.previousVerseId(verseId);
    final next = repo.nextVerseId(verseId);
    final translations = verse.textsOfKind('translation');

    return Scaffold(
      appBar: AppBar(title: Text('${l.chapterNumber(verse.chapter)} · ${l.verseRef(verse.id)}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          VerseTextView(verse: verse),
          const SizedBox(height: 16),
          ProvenanceNote(
            sourceId: verse.sourceId,
            reviewStatus: verse.reviewStatus,
            textAlign: TextAlign.center,
          ),
          if (!verse.isCanonical) ...[
            const SizedBox(height: 16),
            _Notice(text: l.nonCanonicalNote, icon: Icons.info_outline),
          ],
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 20),
          if (translations.isEmpty)
            _Notice(text: l.translationsPending, icon: Icons.translate)
          else
            for (final t in translations) ...[
              Text(t.body, style: theme.textTheme.bodyLarge?.copyWith(height: 1.6)),
              ProvenanceNote(sourceId: t.sourceId, reviewStatus: t.reviewStatus),
              const SizedBox(height: 16),
            ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: prev == null ? null : () => context.pushReplacement('/verse/$prev'),
                icon: const Icon(Icons.chevron_left),
                label: Text(l.previousVerse),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: next == null ? null : () => context.pushReplacement('/verse/$next'),
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

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.icon});

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
