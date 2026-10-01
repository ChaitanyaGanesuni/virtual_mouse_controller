import '../../core/content/models.dart';

/// Tutor modes: the six explanation modes plus free conversation.
enum TutorMode {
  free('free'),
  simple('simple'),
  deep('deep'),
  practical('practical'),
  story('story'),
  child('child'),
  sanskritTerms('sanskrit_terms');

  const TutorMode(this.wire);
  final String wire;

  static TutorMode fromWire(String? s) => values.firstWhere((m) => m.wire == s, orElse: () => TutorMode.free);

  static TutorMode fromExplanation(ExplanationMode m) => fromWire(m.kind);
}

class Citation {
  const Citation({required this.verse, this.sourceId});

  final String verse;
  final String? sourceId;

  factory Citation.fromJson(Map<String, dynamic> j) =>
      Citation(verse: j['verse'] as String, sourceId: j['source_id'] as String?);
}

class TutorMessage {
  const TutorMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.mode,
    this.model,
    this.language,
    this.citations = const [],
    this.uncertainPoints = const [],
    this.confidence,
    this.flags = const [],
    this.support,
    this.outOfScope = false,
  });

  final String id;
  final String role;
  final String content;
  final DateTime createdAt;
  final String? mode;
  final String? model;
  final String? language;

  /// Verses the server checked: they exist and were given to the model.
  final List<Citation> citations;
  final List<String> uncertainPoints;
  final String? confidence;

  /// What the server changed while validating: citations_removed,
  /// unverified_quotes, repaired, cached.
  final List<String> flags;

  /// A helpline note when the question suggested distress.
  final String? support;
  final bool outOfScope;

  bool get isAnswer => role == 'assistant';

  factory TutorMessage.fromJson(Map<String, dynamic> j) => TutorMessage(
    id: j['id'] as String,
    role: j['role'] as String,
    content: j['content'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    mode: j['mode'] as String?,
    model: j['model'] as String?,
    language: j['language'] as String?,
    citations: [
      for (final c in (j['citations'] as List? ?? const [])) Citation.fromJson(c as Map<String, dynamic>),
    ],
    uncertainPoints: [for (final u in (j['uncertain_points'] as List? ?? const [])) u as String],
    confidence: j['confidence'] as String?,
    flags: [for (final f in (j['flags'] as List? ?? const [])) f as String],
    support: j['support'] as String?,
    outOfScope: j['out_of_scope'] as bool? ?? false,
  );
}

class Conversation {
  const Conversation({
    required this.id,
    required this.updatedAt,
    this.title,
    this.pinnedVerseId,
    this.mode = TutorMode.free,
    this.language = 'en',
  });

  final String id;
  final String? title;
  final String? pinnedVerseId;
  final TutorMode mode;
  final String language;
  final DateTime updatedAt;

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
    id: j['id'] as String,
    title: j['title'] as String?,
    pinnedVerseId: j['pinned_verse_id'] as String?,
    mode: TutorMode.fromWire(j['mode'] as String?),
    language: j['language'] as String? ?? 'en',
    updatedAt: DateTime.parse(j['updated_at'] as String),
  );
}

class TutorStatus {
  const TutorStatus({required this.available, required this.dailyLimit, required this.questionsLeft});

  final bool available;
  final int dailyLimit;
  final int questionsLeft;

  factory TutorStatus.fromJson(Map<String, dynamic> j) => TutorStatus(
    available: j['available'] as bool,
    dailyLimit: j['daily_limit'] as int,
    questionsLeft: j['questions_left_today'] as int,
  );
}
