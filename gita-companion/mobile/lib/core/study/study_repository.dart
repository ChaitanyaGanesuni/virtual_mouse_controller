import 'dart:math';

import 'package:drift/drift.dart';

import '../db/user_database.dart';
import '../db/watch.dart';
import 'srs.dart';

typedef Bookmark = BookmarksTableData;
typedef StudyNote = NotesTableData;
typedef StudyHighlight = HighlightsTableData;
typedef RevisionCard = RevisionItemsTableData;
typedef DayPractice = DailyPracticesTableData;

enum NoteKind {
  note,
  question,
  reflection;

  static NoteKind fromWire(String s) => NoteKind.values.firstWhere((k) => k.name == s);
}

enum PracticeStep { listen, understand, reflect, apply }

const highlightColors = ['gold', 'green', 'blue', 'pink'];

/// Everything the reader shows about the user's relation to one verse.
class VerseStudy {
  const VerseStudy({
    this.bookmarked = false,
    this.favorite = false,
    this.understood = false,
    this.needsRevision = false,
    this.notes = const [],
    this.highlights = const [],
  });

  final bool bookmarked;
  final bool favorite;
  final bool understood;
  final bool needsRevision;
  final List<StudyNote> notes;
  final List<StudyHighlight> highlights;
}

/// Calm progress figures ("Chapter 2 · 14 of 72 verses"), no streaks.
class StudyProgress {
  const StudyProgress({
    this.readPerChapter = const {},
    this.understood = 0,
    this.favorites = 0,
    this.cards = 0,
    this.cardsDue = 0,
    this.cardsSettled = 0,
  });

  final Map<int, int> readPerChapter;
  final int understood;
  final int favorites;
  final int cards;
  final int cardsDue;

  /// Cards remembered over a week or more (step ≥ 4 on the ladder): how
  /// much has been retained, not how much was clicked through.
  final int cardsSettled;

  int get versesRead => readPerChapter.values.fold(0, (a, b) => a + b);
}

/// The user's study data on this device ("My Gita"). Local-first: every
/// change is written here at once and marked dirty; SyncService sends it
/// to the server when sync is on.
class StudyRepository {
  StudyRepository(this.db, {DateTime Function()? clock, SrsScheduler? scheduler})
    : clock = clock ?? DateTime.now,
      scheduler = scheduler ?? const LadderScheduler();

  final UserDatabase db;
  final DateTime Function() clock;
  final SrsScheduler scheduler;

  static const settledStep = 4;

  int get _now => clock().toUtc().millisecondsSinceEpoch;

  /// Local calendar date, the key of Daily Practice ('2026-10-06').
  String today() => dateKey(clock());

  static String dateKey(DateTime t) {
    final d = t.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Stream<T> _watch<T>(List<TableInfo<Table, dynamic>> tables, Future<T> Function() load) =>
      watchTables(db, tables, load);

  // -- one verse ----------------------------------------------------------------

  Future<VerseStudy> verse(String verseId) async {
    final b = await (db.select(db.bookmarksTable)..where((t) => t.verseId.equals(verseId))).getSingleOrNull();
    final s = await (db.select(
      db.verseStatesTable,
    )..where((t) => t.verseId.equals(verseId))).getSingleOrNull();
    final notes =
        await (db.select(db.notesTable)
              ..where((t) => t.verseId.equals(verseId) & t.deleted.not())
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
            .get();
    final highlights =
        await (db.select(db.highlightsTable)
              ..where((t) => t.verseId.equals(verseId) & t.deleted.not())
              ..orderBy([(t) => OrderingTerm.asc(t.start)]))
            .get();
    return VerseStudy(
      bookmarked: b != null && !b.deleted,
      favorite: s?.favorite ?? false,
      understood: s?.understood ?? false,
      needsRevision: s?.needsRevision ?? false,
      notes: notes,
      highlights: highlights,
    );
  }

  Stream<VerseStudy> watchVerse(String verseId) => _watch([
    db.bookmarksTable,
    db.verseStatesTable,
    db.notesTable,
    db.highlightsTable,
  ], () => verse(verseId));

  Future<void> setBookmarked(String verseId, bool on) async {
    final now = _now;
    await db
        .into(db.bookmarksTable)
        .insert(
          BookmarksTableCompanion.insert(
            verseId: verseId,
            createdAt: now,
            updatedAt: now,
            deleted: Value(!on),
          ),
          onConflict: DoUpdate(
            (_) =>
                BookmarksTableCompanion(updatedAt: Value(now), deleted: Value(!on), dirty: const Value(true)),
          ),
        );
  }

  Future<void> setFavorite(String verseId, bool on) => _setState(verseId, favorite: on);

  Future<void> setUnderstood(String verseId, bool on) => _setState(verseId, understood: on);

  /// Adds the verse to revision (two cards: its meaning, and how to apply
  /// it a day later) or takes it out.
  Future<void> setNeedsRevision(String verseId, bool on) => db.transaction(() async {
    await _setState(verseId, needsRevision: on);
    if (on) {
      await _addCard(verseId, CardType.meaning, scheduler.start(clock()).dueAt);
      await _addCard(
        verseId,
        CardType.application,
        scheduler.start(clock()).dueAt.add(const Duration(days: 1)),
      );
    } else {
      await (db.update(
        db.revisionItemsTable,
      )..where((t) => t.verseId.equals(verseId) & t.deleted.not())).write(
        RevisionItemsTableCompanion(
          deleted: const Value(true),
          updatedAt: Value(_now),
          dirty: const Value(true),
        ),
      );
    }
  });

  Future<void> _setState(String verseId, {bool? favorite, bool? understood, bool? needsRevision}) async {
    final now = _now;
    final current = await (db.select(
      db.verseStatesTable,
    )..where((t) => t.verseId.equals(verseId))).getSingleOrNull();
    await db
        .into(db.verseStatesTable)
        .insertOnConflictUpdate(
          VerseStatesTableCompanion.insert(
            verseId: verseId,
            favorite: Value(favorite ?? current?.favorite ?? false),
            understood: Value(understood ?? current?.understood ?? false),
            needsRevision: Value(needsRevision ?? current?.needsRevision ?? false),
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
  }

  Future<void> _addCard(String verseId, CardType type, DateTime due) async {
    final now = _now;
    final existing = await (db.select(
      db.revisionItemsTable,
    )..where((t) => t.verseId.equals(verseId) & t.cardType.equals(type.name))).getSingleOrNull();
    if (existing != null && !existing.deleted) return;
    // New, or revived after removal: starts again from the bottom.
    await db
        .into(db.revisionItemsTable)
        .insertOnConflictUpdate(
          RevisionItemsTableCompanion.insert(
            verseId: verseId,
            cardType: type.name,
            state: const Value('new'),
            step: const Value(0),
            dueAt: due.toUtc().millisecondsSinceEpoch,
            reps: const Value(0),
            lapses: const Value(0),
            lastReviewedAt: const Value(null),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            deleted: const Value(false),
            dirty: const Value(true),
          ),
        );
  }

  // -- notes and highlights -------------------------------------------------------

  /// Creates a note (no [id]) or edits one. Returns its id.
  Future<String> saveNote({
    String? id,
    String? verseId,
    int? chapter,
    NoteKind kind = NoteKind.note,
    required String body,
  }) async {
    final now = _now;
    final noteId = id ?? newId();
    final existing = id == null
        ? null
        : await (db.select(db.notesTable)..where((t) => t.id.equals(id))).getSingleOrNull();
    await db
        .into(db.notesTable)
        .insertOnConflictUpdate(
          NotesTableCompanion.insert(
            id: noteId,
            verseId: Value(verseId ?? existing?.verseId),
            chapter: Value(chapter ?? existing?.chapter),
            kind: Value(kind.name),
            body: body,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            deleted: const Value(false),
            dirty: const Value(true),
          ),
        );
    return noteId;
  }

  Future<void> deleteNote(String id) => (db.update(db.notesTable)..where((t) => t.id.equals(id))).write(
    NotesTableCompanion(deleted: const Value(true), updatedAt: Value(_now), dirty: const Value(true)),
  );

  Future<String> addHighlight({
    required String verseId,
    String? textId,
    required int start,
    required int end,
    String color = 'gold',
  }) async {
    final now = _now;
    final id = newId();
    await db
        .into(db.highlightsTable)
        .insert(
          HighlightsTableCompanion.insert(
            id: id,
            verseId: verseId,
            textId: Value(textId),
            start: start,
            end: end,
            color: Value(color),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> deleteHighlight(String id) =>
      (db.update(db.highlightsTable)..where((t) => t.id.equals(id))).write(
        HighlightsTableCompanion(
          deleted: const Value(true),
          updatedAt: Value(_now),
          dirty: const Value(true),
        ),
      );

  // -- lists for My Gita ------------------------------------------------------------

  Stream<List<Bookmark>> watchBookmarks() => _watch(
    [db.bookmarksTable],
    () =>
        (db.select(db.bookmarksTable)
              ..where((t) => t.deleted.not())
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
            .get(),
  );

  Stream<List<String>> watchFavorites() => _watch([db.verseStatesTable], () async {
    final rows =
        await (db.select(db.verseStatesTable)
              ..where((t) => t.favorite)
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
            .get();
    return [for (final r in rows) r.verseId];
  });

  Stream<List<StudyNote>> watchNotes() => _watch(
    [db.notesTable],
    () =>
        (db.select(db.notesTable)
              ..where((t) => t.deleted.not())
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
            .get(),
  );

  Stream<List<StudyHighlight>> watchHighlights() => _watch(
    [db.highlightsTable],
    () =>
        (db.select(db.highlightsTable)
              ..where((t) => t.deleted.not())
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
            .get(),
  );

  // -- reading progress ---------------------------------------------------------------

  /// The reader opened [verseId].
  Future<void> markRead(String verseId) async {
    final now = _now;
    final chapter = int.parse(verseId.split('.').first);
    await db.transaction(() async {
      final existing = await (db.select(
        db.versesReadTable,
      )..where((t) => t.verseId.equals(verseId))).getSingleOrNull();
      await db
          .into(db.versesReadTable)
          .insertOnConflictUpdate(
            VersesReadTableCompanion.insert(
              verseId: verseId,
              firstReadAt: existing?.firstReadAt ?? now,
              lastReadAt: now,
              readCount: Value((existing?.readCount ?? 0) + 1),
              dirty: const Value(true),
            ),
          );
      await db
          .into(db.readingProgressTable)
          .insertOnConflictUpdate(
            ReadingProgressTableCompanion.insert(
              chapter: Value(chapter),
              lastVerseId: verseId,
              updatedAt: now,
              dirty: const Value(true),
            ),
          );
    });
  }

  /// Where to continue reading: the most recently read verse.
  Stream<String?> watchContinue() => _watch([db.readingProgressTable], () async {
    final row =
        await (db.select(db.readingProgressTable)
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
              ..limit(1))
            .getSingleOrNull();
    return row?.lastVerseId;
  });

  Future<StudyProgress> progress() async {
    final perChapter = <int, int>{};
    for (final r in await db.select(db.versesReadTable).get()) {
      final ch = int.parse(r.verseId.split('.').first);
      perChapter[ch] = (perChapter[ch] ?? 0) + 1;
    }
    final states = await db.select(db.verseStatesTable).get();
    final cards = await (db.select(db.revisionItemsTable)..where((t) => t.deleted.not())).get();
    final due = _endOfToday();
    return StudyProgress(
      readPerChapter: perChapter,
      understood: states.where((s) => s.understood).length,
      favorites: states.where((s) => s.favorite).length,
      cards: cards.length,
      cardsDue: cards.where((c) => c.dueAt <= due).length,
      cardsSettled: cards.where((c) => c.step >= settledStep).length,
    );
  }

  Stream<StudyProgress> watchProgress() =>
      _watch([db.versesReadTable, db.verseStatesTable, db.revisionItemsTable], progress);

  // -- revision ------------------------------------------------------------------------

  int _endOfToday() {
    final now = clock().toLocal();
    return DateTime(now.year, now.month, now.day + 1).toUtc().millisecondsSinceEpoch;
  }

  /// Cards due today, the most overdue first.
  Future<List<RevisionCard>> dueCards() =>
      (db.select(db.revisionItemsTable)
            ..where((t) => t.deleted.not() & t.dueAt.isSmallerThanValue(_endOfToday()))
            ..orderBy([(t) => OrderingTerm.asc(t.dueAt), (t) => OrderingTerm.asc(t.verseId)]))
          .get();

  Future<RevisionCard?> card(String verseId, String cardType) => (db.select(
    db.revisionItemsTable,
  )..where((t) => t.verseId.equals(verseId) & t.cardType.equals(cardType))).getSingleOrNull();

  Stream<int> watchDueCount() => _watch([db.revisionItemsTable], () async => (await dueCards()).length);

  CardSchedule scheduleOf(RevisionCard c) => CardSchedule(
    step: c.step,
    dueAt: DateTime.fromMillisecondsSinceEpoch(c.dueAt, isUtc: true),
    state: c.state,
    reps: c.reps,
    lapses: c.lapses,
    lastReviewedAt: c.lastReviewedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(c.lastReviewedAt!, isUtc: true),
  );

  /// Records a self-graded review and schedules the card's next showing.
  Future<CardSchedule> review(RevisionCard card, Rating rating) async {
    final nowDt = clock().toUtc();
    final now = nowDt.millisecondsSinceEpoch;
    final before = scheduleOf(card);
    final next = scheduler.review(before, rating, nowDt);
    final dayMs = const Duration(days: 1).inMilliseconds;
    await db.transaction(() async {
      await (db.update(
        db.revisionItemsTable,
      )..where((t) => t.verseId.equals(card.verseId) & t.cardType.equals(card.cardType))).write(
        RevisionItemsTableCompanion(
          step: Value(next.step),
          state: Value(next.state),
          dueAt: Value(next.dueAt.millisecondsSinceEpoch),
          reps: Value(next.reps),
          lapses: Value(next.lapses),
          lastReviewedAt: Value(now),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      await db
          .into(db.revisionReviewsTable)
          .insert(
            RevisionReviewsTableCompanion.insert(
              id: newId(),
              verseId: card.verseId,
              cardType: card.cardType,
              rating: rating.value,
              reviewedAt: now,
              elapsedDays: Value(
                card.lastReviewedAt == null ? null : max(0, now - card.lastReviewedAt!) / dayMs,
              ),
              scheduledDays: Value((next.dueAt.millisecondsSinceEpoch - now) / dayMs),
            ),
          );
    });
    return next;
  }

  // -- daily practice -------------------------------------------------------------------

  Future<DayPractice?> practice(String date) =>
      (db.select(db.dailyPracticesTable)..where((t) => t.date.equals(date))).getSingleOrNull();

  Stream<DayPractice?> watchPractice(String date) => _watch([db.dailyPracticesTable], () => practice(date));

  Future<void> completeStep(String date, String verseId, PracticeStep step) async {
    final now = _now;
    final at = Value<int?>(now);
    await _upsertPractice(date, verseId, switch (step) {
      PracticeStep.listen => DailyPracticesTableCompanion(listenedAt: at),
      PracticeStep.understand => DailyPracticesTableCompanion(understoodAt: at),
      PracticeStep.reflect => DailyPracticesTableCompanion(reflectedAt: at),
      PracticeStep.apply => DailyPracticesTableCompanion(appliedAt: at),
    });
  }

  Future<void> saveJournal(String date, String verseId, String text) =>
      _upsertPractice(date, verseId, DailyPracticesTableCompanion(journal: Value(text)));

  Future<void> _upsertPractice(String date, String verseId, DailyPracticesTableCompanion change) async {
    final now = _now;
    await db.transaction(() async {
      final existing = await practice(date);
      if (existing == null) {
        await db
            .into(db.dailyPracticesTable)
            .insert(DailyPracticesTableCompanion.insert(date: date, verseId: verseId, updatedAt: now));
      }
      await (db.update(db.dailyPracticesTable)..where((t) => t.date.equals(date))).write(
        change.copyWith(updatedAt: Value(now), deleted: const Value(false), dirty: const Value(true)),
      );
    });
  }

  /// Journal entries, newest first.
  Stream<List<DayPractice>> watchJournal() => _watch(
    [db.dailyPracticesTable],
    () =>
        (db.select(db.dailyPracticesTable)
              ..where((t) => t.deleted.not() & t.journal.equals('').not())
              ..orderBy([(t) => OrderingTerm.desc(t.date)]))
            .get(),
  );
}

final _random = Random.secure();

/// A random (version 4) UUID.
String newId() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
