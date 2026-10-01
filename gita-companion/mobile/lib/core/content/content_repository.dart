import 'models.dart';

/// Read access to scripture content. The app depends on this interface;
/// the bundled SQLite pack is one implementation (tests use fakes).
abstract interface class ContentRepository {
  List<Chapter> chapters();

  Chapter chapter(int number);

  /// All stored verses of a chapter in reading order (13.0 comes first in 13).
  List<Verse> versesOf(int chapter);

  /// A single verse with its texts, or null if [id] does not exist.
  Verse? verse(String id);

  /// Every verse id in reading order (1.1 … 18.78, including 13.0).
  List<String> readingOrder();

  /// The verse before/after [id] in reading order across chapters.
  String? previousVerseId(String id);
  String? nextVerseId(String id);

  Source? source(String id);

  /// The "X uvāca" speakers, used to style speaker headings inside verses.
  List<Speaker> speakers();

  /// Every source the installed content comes from (for the licences screen).
  List<Source> sources();

  /// Deterministic verse of the day: the same canonical verse for everyone
  /// on a given calendar date.
  Verse verseOfTheDay(DateTime date);
}
