import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../content/models.dart';
import 'text_prep.dart';

/// What a chunk is: Sanskrit recitation (dedicated recitation pipeline) or
/// ordinary speech (explanations, translations).
enum ChunkKind { recitation, speech }

/// One synthesizable piece of a playlist.
class AudioChunk {
  const AudioChunk({
    required this.id,
    required this.text,
    required this.language,
    required this.kind,
    required this.section,
    this.verseId,
    this.rate = 1.0,
    String? displayText,
  }) : displayText = displayText ?? text;

  /// `<manifest id>/c0007`
  final String id;

  /// Text sent to the speech engine (normalised: dandas → pauses, verse
  /// references spelled out).
  final String text;

  /// The same passage as the reader sees it on screen.
  final String displayText;

  /// 'sa' for recitation, else the speech language ('en', 'te').
  final String language;
  final ChunkKind kind;

  /// 'recitation', 'simple', 'deep', … for display ("Current section").
  final String section;
  final String? verseId;

  /// Synthesis-level rate (slow recitation = 0.7). Playback speed is separate.
  final double rate;

  double get estimatedSeconds => estimateSeconds(text, language, rate: rate);
}

/// An ordered playlist for one listenable unit.
class AudioManifest {
  AudioManifest({
    required this.id,
    required this.title,
    required this.chunks,
    this.chapter,
    this.repeat = 1,
    this.ephemeral = false,
  }) : assert(chunks.isNotEmpty);

  /// Stable for the same content and options, so saved progress can resume.
  final String id;
  final String title;
  final int? chapter;
  final List<AudioChunk> chunks;

  /// How many times the whole manifest plays (Repeat ×3 for recitation).
  final int repeat;

  /// Previews and samples: never saved as listening progress.
  final bool ephemeral;

  int indexOfVerse(String verseId) => chunks.indexWhere((c) => c.verseId == verseId);
}

/// Content-addressed cache key. Playback speed is deliberately NOT included:
/// audio is synthesized once and sped up by the player. The provider version
/// is included so upgrading a voice never serves stale audio.
String audioHash({
  required String text,
  required String language,
  required String provider,
  required String providerVersion,
  required String voice,
  required double rate,
}) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final key = [normalized, language, provider, providerVersion, voice, rate.toStringAsFixed(2)].join('|');
  return sha256.convert(utf8.encode(key)).toString();
}

/// Builds manifests for the app's listening entry points.
class ManifestBuilder {
  const ManifestBuilder();

  /// Sanskrit recitation of one verse: speaker heading and one chunk per
  /// half-verse line (natural pauses between lines).
  AudioManifest recitation(Verse verse, {bool slow = false, int repeat = 1}) {
    final rate = slow ? 0.7 : 1.0;
    final id = 'recite-${verse.id}-${slow ? 'slow' : 'normal'}${repeat > 1 ? '-x$repeat' : ''}';
    return AudioManifest(
      id: id,
      title: verse.id,
      chapter: verse.chapter,
      repeat: repeat,
      chunks: _recitationChunks(verse, id, rate),
    );
  }

  /// One explanation mode of one verse, in one language.
  AudioManifest? explanation(Verse verse, VerseText text) {
    final id = 'explain-${verse.id}-${text.kind}-${text.language}';
    final chunks = _speechChunks(speakableBody(text), text.language, id, text.kind, verse.id, 0);
    return chunks.isEmpty
        ? null
        : AudioManifest(id: id, title: verse.id, chapter: verse.chapter, chunks: chunks);
  }

  /// "Read this verse": recitation followed by an explanation (if any).
  AudioManifest verseWithExplanation(Verse verse, VerseText? explanation) {
    final id = 'verse-${verse.id}-${explanation?.kind ?? 'none'}-${explanation?.language ?? 'sa'}';
    final chunks = _recitationChunks(verse, id, 1.0);
    if (explanation != null) {
      chunks.addAll(
        _speechChunks(
          speakableBody(explanation),
          explanation.language,
          id,
          explanation.kind,
          verse.id,
          chunks.length,
        ),
      );
    }
    return AudioManifest(id: id, title: verse.id, chapter: verse.chapter, chunks: chunks);
  }

  /// "Read entire chapter": every verse recited, each followed by its
  /// explanation in [language] when one exists.
  AudioManifest chapter(
    int number,
    List<Verse> verses, {
    required VerseText? Function(Verse) explanationFor,
    String language = 'en',
  }) {
    final id = 'chapter-$number-$language';
    final chunks = <AudioChunk>[];
    for (final v in verses) {
      chunks.addAll(_recitationChunks(v, id, 1.0, start: chunks.length));
      final e = explanationFor(v);
      if (e != null) {
        chunks.addAll(_speechChunks(speakableBody(e), e.language, id, e.kind, v.id, chunks.length));
      }
    }
    return AudioManifest(id: id, title: 'chapter $number', chapter: number, chunks: chunks);
  }

  List<AudioChunk> _recitationChunks(Verse verse, String id, double rate, {int start = 0}) {
    final lines = [if (verse.speaker != null) verse.speaker!.lines['sa']!, ...verse.sanskrit.split('\n')];
    return [
      for (var i = 0; i < lines.length; i++)
        AudioChunk(
          id: '$id/c${(start + i).toString().padLeft(4, '0')}',
          text: normalizeForSpeech(lines[i], 'sa'),
          displayText: lines[i],
          language: 'sa',
          kind: ChunkKind.recitation,
          section: 'recitation',
          verseId: verse.id,
          rate: rate,
        ),
    ];
  }

  List<AudioChunk> _speechChunks(
    String body,
    String language,
    String id,
    String section,
    String verseId,
    int start,
  ) {
    final pieces = chunkText(normalizeForSpeech(body, language));
    return [
      for (var i = 0; i < pieces.length; i++)
        AudioChunk(
          id: '$id/c${(start + i).toString().padLeft(4, '0')}',
          text: pieces[i],
          language: language,
          kind: ChunkKind.speech,
          section: section,
          verseId: verseId,
        ),
    ];
  }
}

/// Text to read aloud for a verse text. "Sanskrit terms" are stored as JSON
/// and are spoken as "term: meaning." sentences.
String speakableBody(VerseText text) {
  if (text.kind != 'sanskrit_terms') return text.body;
  try {
    final items = (jsonDecode(text.body) as List).cast<Map<String, dynamic>>();
    return items
        .map((t) => '${t['term']}: ${t['meaning']}'.trim())
        .map((s) => s.endsWith('.') ? s : '$s.')
        .join(' ');
  } on Object {
    return text.body;
  }
}

/// A one-off sample for the voice settings screen (never saved as progress).
AudioManifest previewManifest(String language, String text) => AudioManifest(
  id: 'preview-$language',
  title: 'preview',
  ephemeral: true,
  chunks: [
    AudioChunk(
      id: 'preview-$language/c0000',
      text: normalizeForSpeech(text, language),
      language: language,
      kind: language == 'sa' ? ChunkKind.recitation : ChunkKind.speech,
      section: language == 'sa' ? 'recitation' : 'preview',
    ),
  ],
);
