import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/theme.dart';
import '../core/content/models.dart';

/// Renders a verse in the user's chosen script, with the speaker heading
/// and (optionally) the IAST transliteration underneath.
class VerseTextView extends ConsumerWidget {
  const VerseTextView({
    super.key,
    required this.verse,
    this.compact = false,
    this.textAlign = TextAlign.center,
  });

  final Verse verse;

  /// Compact: smaller text, no speaker heading, no transliteration (for cards/lists).
  final bool compact;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final script = s.verseScript;
    final scale = s.textScale * (compact ? 0.8 : 1.0);
    final showIast = s.showTransliteration && script != VerseScript.iast && !compact;
    // Speaker headings that occur inside a verse (e.g. 1.28 "arjuna uvāca").
    final headings = {for (final sp in ref.watch(contentRepositoryProvider).speakers()) ...sp.lines.values};
    final align = textAlign == TextAlign.center ? CrossAxisAlignment.center : CrossAxisAlignment.start;

    return Column(
      crossAxisAlignment: align,
      children: [
        if (verse.speaker != null && !compact) ...[
          Text(
            verse.speaker!.lines[script.tag] ?? verse.speaker!.lines['sa']!,
            style: ScriptureStyles.speaker(context, script, scale),
            textAlign: textAlign,
          ),
          const SizedBox(height: 4),
        ],
        Text.rich(
          _verseSpan(verse.textIn(script), headings, ScriptureStyles.speaker(context, script, scale)),
          style: ScriptureStyles.verse(context, script, scale),
          textAlign: textAlign,
          // Sanskrit should be read by screen readers in its own language.
          locale: Locale(script == VerseScript.telugu ? 'te' : 'sa'),
        ),
        if (showIast) ...[
          const SizedBox(height: 12),
          Text(
            keepDandaWithWord(verse.textIn(VerseScript.iast)),
            style: ScriptureStyles.transliteration(context, s.textScale),
            textAlign: textAlign,
          ),
        ],
      ],
    );
  }
}

/// Joins a danda to the preceding word with a no-break space, so "॥" never
/// wraps onto a line of its own.
String keepDandaWithWord(String text) => text.replaceAllMapped(RegExp(' ([।॥])'), (m) => '\u00A0${m[1]}');

TextSpan _verseSpan(String text, Set<String> headings, TextStyle headingStyle) {
  final lines = text.split('\n');
  return TextSpan(
    children: [
      for (var i = 0; i < lines.length; i++)
        TextSpan(
          text: keepDandaWithWord(lines[i]) + (i < lines.length - 1 ? '\n' : ''),
          style: headings.contains(lines[i]) ? headingStyle : null,
        ),
    ],
  );
}
