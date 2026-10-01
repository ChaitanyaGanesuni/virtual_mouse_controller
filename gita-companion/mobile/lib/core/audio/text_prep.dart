/// Text preparation for speech: normalise → split into sentences → pack into
/// chunks. Long text is never sent to a TTS engine in one piece; each chunk
/// becomes one cached audio file, and the player moves from chunk to chunk.
library;

const maxChunkChars = 300;
const minChunkChars = 60;

// "2.47" or "(18.66)." – a sentence's full stop must not hide a reference,
// but parts of longer numbers ("1.2.3", "10.234") are not references.
final _verseRef = RegExp(r'(?<!\d)(?<!\d\.)(\d{1,2})\.(\d{1,2})(?!\d)(?!\.\d)');
final _spaces = RegExp(r'\s+');

/// Makes text speakable in [language] ('en', 'te', 'sa').
String normalizeForSpeech(String text, String language) {
  var s = text;
  if (language != 'sa') {
    // "2.47" is read as "two point four seven"; say "chapter 2, verse 47".
    s = s.replaceAllMapped(
      _verseRef,
      (m) => language == 'te' ? 'అధ్యాయం ${m[1]}, శ్లోకం ${m[2]}' : 'chapter ${m[1]}, verse ${m[2]}',
    );
  }
  // Dandas end a phrase: keep the pause, drop the glyph.
  s = s.replaceAll('॥', '.').replaceAll('।', ',');
  s = s.replaceAll(RegExp(r'[«»*_#]'), '');
  return s.replaceAll(_spaces, ' ').trim();
}

/// Splits into sentences on . ! ? and the danda (already normalised to "."),
/// keeping the punctuation with its sentence.
List<String> splitSentences(String text) {
  // Split only where punctuation is followed by a space, so decimals such
  // as "1.5" stay inside their sentence.
  return text.split(RegExp(r'(?<=[.!?])\s+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
}

/// Packs sentences into chunks of at most [maxChars]. A sentence longer than
/// that is split at commas/semicolons, and as a last resort between words.
List<String> chunkText(String text, {int maxChars = maxChunkChars}) {
  final pieces = <String>[];
  for (final sentence in splitSentences(text)) {
    if (sentence.length <= maxChars) {
      pieces.add(sentence);
      continue;
    }
    pieces.addAll(_splitLong(sentence, maxChars));
  }
  final chunks = <String>[];
  var current = '';
  for (final p in pieces) {
    if (current.isEmpty) {
      current = p;
    } else if (current.length + 1 + p.length <= maxChars) {
      current = '$current $p';
    } else {
      chunks.add(current);
      current = p;
    }
  }
  if (current.isNotEmpty) chunks.add(current);
  // Avoid a tiny trailing chunk (a short gap of silence between files is
  // more noticeable than a slightly longer chunk).
  if (chunks.length >= 2 && chunks.last.length < minChunkChars) {
    final merged = '${chunks[chunks.length - 2]} ${chunks.last}';
    if (merged.length <= maxChars) {
      chunks
        ..removeLast()
        ..[chunks.length - 1] = merged;
    }
  }
  return chunks;
}

List<String> _splitLong(String sentence, int maxChars) {
  final parts = sentence.split(RegExp(r'(?<=[,;:])\s+'));
  final out = <String>[];
  var current = '';
  for (final part in parts) {
    for (final piece in part.length <= maxChars ? [part] : _byWords(part, maxChars)) {
      if (current.isEmpty) {
        current = piece;
      } else if (current.length + 1 + piece.length <= maxChars) {
        current = '$current $piece';
      } else {
        out.add(current);
        current = piece;
      }
    }
  }
  if (current.isNotEmpty) out.add(current);
  return out;
}

List<String> _byWords(String text, int maxChars) {
  final out = <String>[];
  var current = '';
  for (final w in text.split(' ')) {
    if (current.isNotEmpty && current.length + 1 + w.length > maxChars) {
      out.add(current);
      current = w;
    } else {
      current = current.isEmpty ? w : '$current $w';
    }
  }
  if (current.isNotEmpty) out.add(current);
  return out;
}

/// Rough spoken duration, used for the timeline before a chunk's real
/// duration is known (then the real one replaces it).
double estimateSeconds(String text, String language, {double rate = 1.0}) {
  final charsPerSecond = switch (language) {
    'te' => 11.0,
    'sa' => 9.0,
    _ => 14.0,
  };
  return (text.length / charsPerSecond / rate).clamp(0.5, 600.0);
}
