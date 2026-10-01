import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/audio/manifest.dart';
import '../../core/content/models.dart';
import '../../l10n/app_localizations.dart';

/// Starts [manifest] and opens the full player.
Future<void> startListening(
  BuildContext context,
  WidgetRef ref,
  AudioManifest manifest, {
  bool resume = true,
}) async {
  final player = ref.read(playbackControllerProvider);
  final router = GoRouter.of(context);
  // Open the player right away; it shows a loading state while the first
  // chunk is synthesized (which can take a moment on a phone).
  unawaited(player.open(manifest, resume: resume));
  await router.push('/player');
}

enum _RecitationOption { slow, repeat3, repeat3Slow }

/// Listening buttons on the verse screen: recite the Sanskrit (normal, slow,
/// ×3) and "Listen" (recitation followed by the selected explanation).
class VerseListenActions extends ConsumerWidget {
  const VerseListenActions({super.key, required this.verse, required this.explanation});

  final Verse verse;

  /// The explanation currently shown (mode + language), if any.
  final VerseText? explanation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    const builder = ManifestBuilder();
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonalIcon(
          onPressed: () => startListening(context, ref, builder.recitation(verse), resume: false),
          icon: const Icon(Icons.record_voice_over_outlined),
          label: Text(l.recite),
        ),
        PopupMenuButton<_RecitationOption>(
          tooltip: l.listenOptions,
          icon: const Icon(Icons.more_horiz),
          onSelected: (o) => startListening(context, ref, switch (o) {
            _RecitationOption.slow => builder.recitation(verse, slow: true),
            _RecitationOption.repeat3 => builder.recitation(verse, repeat: 3),
            _RecitationOption.repeat3Slow => builder.recitation(verse, slow: true, repeat: 3),
          }, resume: false),
          itemBuilder: (_) => [
            PopupMenuItem(value: _RecitationOption.slow, child: Text(l.reciteSlowly)),
            PopupMenuItem(value: _RecitationOption.repeat3, child: Text(l.repeatThree)),
            PopupMenuItem(value: _RecitationOption.repeat3Slow, child: Text(l.repeatThreeSlowly)),
          ],
        ),
        OutlinedButton.icon(
          onPressed: () => startListening(context, ref, builder.verseWithExplanation(verse, explanation)),
          icon: const Icon(Icons.headphones_outlined),
          label: Text(l.listenVerse),
        ),
      ],
    );
  }
}

/// Small "read this explanation aloud" button for the Understand card.
class ReadExplanationButton extends ConsumerWidget {
  const ReadExplanationButton({super.key, required this.verse, required this.text});

  final Verse verse;
  final VerseText text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final manifest = const ManifestBuilder().explanation(verse, text);
    return IconButton(
      tooltip: l.listenExplanation,
      icon: const Icon(Icons.volume_up_outlined),
      onPressed: manifest == null ? null : () => startListening(context, ref, manifest),
    );
  }
}
