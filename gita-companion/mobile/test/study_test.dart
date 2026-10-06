import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/core/db/user_database.dart';
import 'package:gita_companion/core/study/srs.dart';
import 'package:gita_companion/core/study/study_repository.dart';

void main() {
  group('ladder scheduler (day 1 → 2 → 4 → 7 → 14 …)', () {
    const s = LadderScheduler();
    final t0 = DateTime.utc(2026, 10, 6, 9);
    int days(CardSchedule c, DateTime from) => c.dueAt.difference(from).inDays;

    test('a new card is first due the next day, then climbs with Good', () {
      var card = s.start(t0);
      expect(days(card, t0), 1);
      var now = card.dueAt;
      final waits = <int>[];
      for (var i = 0; i < 5; i++) {
        card = s.review(card, Rating.good, now);
        waits.add(days(card, now));
        now = card.dueAt;
      }
      expect(waits, [2, 4, 7, 14, 30]);
      expect(card.reps, 5);
    });

    test('Again goes back to the start and comes back in the same session', () {
      var card = s.start(t0);
      card = s.review(card, Rating.good, t0);
      card = s.review(card, Rating.good, t0);
      final again = s.review(card, Rating.again, t0);
      expect(again.step, 0);
      expect(again.dueAt.difference(t0), LadderScheduler.relearnDelay);
      expect(again.lapses, 1);
      expect(again.state, 'relearning');
    });

    test('Hard repeats the interval, Easy skips a step, and the ladder tops out', () {
      final card = CardSchedule(step: 2, dueAt: t0, reps: 3);
      expect(days(s.review(card, Rating.hard, t0), t0), 4);
      expect(days(s.review(card, Rating.easy, t0), t0), 14);
      final top = CardSchedule(step: 8, dueAt: t0, reps: 9);
      expect(days(s.review(top, Rating.easy, t0), t0), 240);
      expect(s.preview(card, Rating.good, t0).inDays, 7);
    });
  });

  group('study repository', () {
    late UserDatabase db;
    late StudyRepository repo;
    var now = DateTime.utc(2026, 10, 6, 9);

    setUp(() {
      db = UserDatabase.memory();
      now = DateTime.utc(2026, 10, 6, 9);
      repo = StudyRepository(db, clock: () => now);
    });
    tearDown(() => db.close());

    test('bookmarks, states, notes and highlights of a verse', () async {
      final changes = repo.watchVerse('2.47');
      final seen = <VerseStudy>[];
      final sub = changes.listen(seen.add);

      await repo.setBookmarked('2.47', true);
      await repo.setFavorite('2.47', true);
      await repo.setUnderstood('2.47', true);
      final noteId = await repo.saveNote(
        verseId: '2.47',
        kind: NoteKind.question,
        body: 'Why not the fruits?',
      );
      final hl = await repo.addHighlight(verseId: '2.47', textId: 't1', start: 4, end: 20);

      var v = await repo.verse('2.47');
      expect((v.bookmarked, v.favorite, v.understood, v.needsRevision), (true, true, true, false));
      expect(v.notes.single.body, 'Why not the fruits?');
      expect(v.notes.single.kind, 'question');
      expect(v.highlights.single.id, hl);

      await repo.saveNote(id: noteId, kind: NoteKind.question, body: 'Edited');
      expect((await repo.verse('2.47')).notes.single.body, 'Edited');
      expect((await repo.verse('2.47')).notes.single.verseId, '2.47', reason: 'editing keeps the anchor');

      await repo.setBookmarked('2.47', false);
      await repo.deleteNote(noteId);
      await repo.deleteHighlight(hl);
      v = await repo.verse('2.47');
      expect(v.bookmarked, isFalse);
      expect(v.notes, isEmpty);
      expect(v.highlights, isEmpty);

      // Deletions are tombstones, kept for sync.
      final tomb = await db.select(db.notesTable).getSingle();
      expect((tomb.deleted, tomb.dirty), (true, true));
      await pumpEventQueue();
      expect(seen.length, greaterThan(3));
      expect(seen.last.bookmarked, isFalse);
      await sub.cancel();
    });

    test('a highlight must be a real range', () async {
      expect(() => repo.addHighlight(verseId: '2.47', start: 5, end: 5), throwsA(anything));
      expect(() => repo.addHighlight(verseId: '2.47', start: 0, end: 3, color: 'purple'), throwsA(anything));
    });

    test('revision: marking a verse adds two cards; reviews follow the ladder', () async {
      await repo.setNeedsRevision('2.47', true);
      expect(await repo.dueCards(), isEmpty, reason: 'first due tomorrow');

      now = now.add(const Duration(days: 1));
      final due = await repo.dueCards();
      expect([for (final c in due) c.cardType], ['meaning']);
      final next = await repo.review(due.single, Rating.good);
      expect(next.dueAt.difference(now).inDays, 2);

      final log = await db.select(db.revisionReviewsTable).getSingle();
      expect((log.rating, log.cardType, log.scheduledDays), (3, 'meaning', 2.0));

      now = now.add(const Duration(days: 1));
      expect([for (final c in await repo.dueCards()) c.cardType], ['application']);

      // Taking the verse out of revision removes its cards.
      await repo.setNeedsRevision('2.47', false);
      now = now.add(const Duration(days: 30));
      expect(await repo.dueCards(), isEmpty);
      // Putting it back starts over.
      await repo.setNeedsRevision('2.47', true);
      final revived = await (db.select(db.revisionItemsTable)).get();
      expect(revived.every((c) => !c.deleted && c.step == 0 && c.reps == 0), isTrue);
    });

    test('cards due later today count as due today', () async {
      now = DateTime(2026, 10, 6, 7).toUtc(); // local morning
      await repo.setNeedsRevision('3.19', true);
      now = DateTime(2026, 10, 7, 6).toUtc(); // next morning; card due at 7
      expect((await repo.dueCards()).length, 1);
    });

    test('reading progress and continue learning', () async {
      final cont = <String?>[];
      final sub = repo.watchContinue().listen(cont.add);
      await repo.markRead('2.47');
      now = now.add(const Duration(minutes: 1));
      await repo.markRead('2.48');
      now = now.add(const Duration(minutes: 1));
      await repo.markRead('2.47');
      now = now.add(const Duration(minutes: 1));
      await repo.markRead('3.1');
      final p = await repo.progress();
      expect(p.readPerChapter, {2: 2, 3: 1});
      expect(p.versesRead, 3);
      final read = await (db.select(db.versesReadTable)..where((t) => t.verseId.equals('2.47'))).getSingle();
      expect(read.readCount, 2);
      await pumpEventQueue();
      expect(cont.last, '3.1');
      await sub.cancel();
    });

    test('progress counts what was retained, not what was clicked', () async {
      await repo.setUnderstood('2.47', true);
      await repo.setFavorite('2.48', true);
      await repo.setNeedsRevision('2.47', true);
      var p = await repo.progress();
      expect((p.understood, p.favorites, p.cards, p.cardsDue, p.cardsSettled), (1, 1, 2, 0, 0));
      for (var i = 0; i < 4; i++) {
        now = now.add(const Duration(days: 400));
        final card = (await repo.dueCards()).firstWhere((c) => c.cardType == 'meaning');
        await repo.review(card, Rating.good);
      }
      p = await repo.progress();
      expect(p.cardsSettled, 1);
    });

    test('daily practice steps and journal', () async {
      final date = repo.today();
      expect(date, '2026-10-06');
      await repo.completeStep(date, '2.47', PracticeStep.listen);
      await repo.completeStep(date, '2.47', PracticeStep.reflect);
      await repo.saveJournal(date, '2.47', 'I worried less today.');
      final day = (await repo.practice(date))!;
      expect(day.listenedAt, isNotNull);
      expect(day.understoodAt, isNull);
      expect(day.reflectedAt, isNotNull);
      expect(day.journal, 'I worried less today.');
      expect((await repo.watchJournal().first).single.date, date);
    });

    test('ids are random version-4 UUIDs', () {
      final ids = {for (var i = 0; i < 100; i++) newId()};
      expect(ids, hasLength(100));
      expect(
        ids.first,
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
    });
  });
}
