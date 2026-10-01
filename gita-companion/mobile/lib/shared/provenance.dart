import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/content/models.dart';
import '../l10n/app_localizations.dart';

/// The small source line shown under every piece of content: where it came
/// from, whether it is AI-assisted, and its review status. Scripture, human
/// commentary and AI text must never look interchangeable.
class ProvenanceNote extends ConsumerWidget {
  const ProvenanceNote({
    super.key,
    required this.sourceId,
    required this.reviewStatus,
    this.textAlign = TextAlign.start,
  });

  final String sourceId;
  final ReviewStatus reviewStatus;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final source = ref.watch(contentRepositoryProvider).source(sourceId);
    final theme = Theme.of(context);
    final parts = [
      // Model output names its model; editorial text drafted with AI help
      // keeps its source title plus an "AI-assisted" flag.
      if (source?.kind == 'ai')
        l.aiGeneratedBy(source?.modelId ?? '?')
      else ...[
        l.sourceLabel(source?.title ?? sourceId),
        if (source?.isAiGenerated ?? false) l.aiLabel,
      ],
      reviewLabel(l, reviewStatus),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        parts.join(' · '),
        textAlign: textAlign,
        style: theme.textTheme.bodySmall?.copyWith(
          color: reviewStatus == ReviewStatus.pending ? theme.colorScheme.primary : null,
        ),
      ),
    );
  }
}

String reviewLabel(AppLocalizations l, ReviewStatus s) => switch (s) {
  ReviewStatus.unreviewed => l.reviewUnreviewed,
  ReviewStatus.pending => l.reviewPending,
  ReviewStatus.reviewed => l.reviewReviewed,
  ReviewStatus.rejected => l.reviewRejected,
};
