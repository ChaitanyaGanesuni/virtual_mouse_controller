import '../content/content_repository.dart';
import '../content/models.dart';
import 'manifest.dart';

/// Rebuilds a manifest from its id, so a saved listening position can be
/// resumed after the app restarts. Ids are produced by [ManifestBuilder]:
///   recite-2.47-normal | recite-2.47-slow | recite-2.47-normal-x3
///   explain-2.47-simple-en
///   verse-2.47-simple-en | verse-2.47-none-sa
///   chapter-2-en
class ManifestResolver {
  ManifestResolver(this.repo, [this.builder = const ManifestBuilder()]);

  final ContentRepository repo;
  final ManifestBuilder builder;

  static final _recite = RegExp(r'^recite-(\d+\.\d+)-(normal|slow)(?:-x(\d))?$');
  static final _explain = RegExp(r'^explain-(\d+\.\d+)-([a-z_]+)-([a-z]+)$');
  static final _verse = RegExp(r'^verse-(\d+\.\d+)-([a-z_]+)-([a-z]+)$');
  static final _chapter = RegExp(r'^chapter-(\d+)-([a-z]+)$');

  AudioManifest? resolve(String id) {
    if (_recite.firstMatch(id) case final m?) {
      final v = repo.verse(m[1]!);
      return v == null ? null : builder.recitation(v, slow: m[2] == 'slow', repeat: int.parse(m[3] ?? '1'));
    }
    if (_explain.firstMatch(id) case final m?) {
      final v = repo.verse(m[1]!);
      final t = v?.texts.where((t) => t.kind == m[2] && t.language == m[3]).firstOrNull;
      return (v == null || t == null) ? null : builder.explanation(v, t);
    }
    if (_verse.firstMatch(id) case final m?) {
      final v = repo.verse(m[1]!);
      if (v == null) return null;
      final t = v.texts.where((t) => t.kind == m[2] && t.language == m[3]).firstOrNull;
      return builder.verseWithExplanation(v, t);
    }
    if (_chapter.firstMatch(id) case final m?) {
      final n = int.parse(m[1]!);
      if (n < 1 || n > 18) return null;
      return chapter(n, m[2]!);
    }
    return null;
  }

  /// Every verse recited, each followed by its simple explanation in
  /// [language] when one exists (best available source).
  AudioManifest chapter(int number, String language) => builder.chapter(
    number,
    repo.versesOf(number),
    language: language,
    explanationFor: (v) => pickText(
      v.texts.where((t) => t.kind == 'simple' && t.language == language).toList(),
      language: language,
      languageOf: (t) => t.language,
      statusOf: (t) => t.reviewStatus,
      isAi: (t) => repo.source(t.sourceId)?.kind == 'ai',
    ),
  );
}
