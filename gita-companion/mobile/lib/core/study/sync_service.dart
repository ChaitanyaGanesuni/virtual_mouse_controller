import 'dart:async';

import 'package:drift/drift.dart';

import '../api/api_client.dart';
import '../db/user_database.dart';
import '../db/watch.dart';

/// What the sync settings screen shows.
class SyncStatus {
  const SyncStatus({
    required this.enabled,
    required this.includeJournal,
    this.lastSyncAt,
    this.lastError,
    this.pending = 0,
  });

  final bool enabled;
  final bool includeJournal;
  final DateTime? lastSyncAt;
  final String? lastError;

  /// Changes on this device not yet on the server.
  final int pending;
}

/// Keeps the study data on this device and the server in step
/// (POST /v1/sync, see backend app/modules/sync).
///
/// Off until the user turns it on. Changes are always written locally first
/// (StudyRepository marks them dirty); a sync sends dirty rows, marks them
/// clean if they did not change meanwhile, and merges what other devices
/// changed. Conflicts: the later edit wins, as on the server; reading
/// history merges. The journal is sent only if the user chose to include it.
class SyncService {
  SyncService(this.db, this.api, {DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  final UserDatabase db;
  final ApiClient api;
  final DateTime Function() clock;

  /// Records per request: small enough for slow connections (a note can
  /// be 20,000 characters), well under the server's limit.
  static const batch = 100;

  Future<void>? _running;
  bool _sawJournal = false;

  Future<SyncStateTableData> _state() => db.select(db.syncStateTable).getSingle();

  Future<void> _setState(SyncStateTableCompanion c) => db.update(db.syncStateTable).write(c);

  Future<SyncStatus> status() async {
    final s = await _state();
    var pending = 0;
    for (final t in _dirtyTables) {
      final n =
          await (db.selectOnly(t)
                ..addColumns([countAll()])
                ..where(_dirty(t)))
              .map((r) => r.read(countAll()) ?? 0)
              .getSingle();
      pending += n;
    }
    return SyncStatus(
      enabled: s.enabled,
      includeJournal: s.includeJournal,
      lastSyncAt: s.lastSyncAt == null ? null : DateTime.fromMillisecondsSinceEpoch(s.lastSyncAt!),
      lastError: s.lastError,
      pending: pending,
    );
  }

  Stream<SyncStatus> watchStatus() => watchTables(db, [db.syncStateTable, ..._dirtyTables], status);

  List<TableInfo<Table, dynamic>> get _dirtyTables => [
    db.bookmarksTable,
    db.verseStatesTable,
    db.highlightsTable,
    db.notesTable,
    db.revisionItemsTable,
    db.revisionReviewsTable,
    db.dailyPracticesTable,
    db.versesReadTable,
    db.readingProgressTable,
  ];

  Expression<bool> _dirty(TableInfo<Table, dynamic> t) =>
      (t.columnsByName['dirty']! as GeneratedColumn<bool>).equals(true);

  /// Turning sync on sends everything on this device on the next sync.
  Future<void> setEnabled(bool on) async {
    await db.transaction(() async {
      await _setState(SyncStateTableCompanion(enabled: Value(on), lastError: const Value(null)));
      if (on) await _markAllDirty();
    });
  }

  /// Journal entries are private: they go to the server only if the user
  /// includes them. Turning this off erases them from the server.
  Future<void> setIncludeJournal(bool on) async {
    await db.transaction(() async {
      await _setState(SyncStateTableCompanion(includeJournal: Value(on), eraseJournal: Value(!on)));
      // Publishing or withdrawing the journal is a change: it must win over
      // the server's copy, which is decided by time.
      await db.customUpdate(
        'UPDATE daily_practice SET dirty = 1, updated_at = MAX(updated_at + 1, ?)',
        variables: [Variable.withInt(clock().toUtc().millisecondsSinceEpoch)],
        updates: {db.dailyPracticesTable},
      );
    });
  }

  Future<void> _markAllDirty() async {
    for (final t in _dirtyTables) {
      await db.customUpdate('UPDATE ${t.actualTableName} SET dirty = 1', updates: {t});
    }
  }

  /// A new recovery code for the account (shown once).
  Future<String> createRecoveryCode() => api.createRecoveryCode();

  /// Signs in to the account [code] belongs to and merges this device's
  /// data with it.
  Future<void> restore(String code) async {
    await _running;
    final account = await api.recover(code);
    await db.transaction(() async {
      await _setState(
        SyncStateTableCompanion(
          enabled: const Value(true),
          cursor: const Value(0),
          accountId: Value(account),
          lastError: const Value(null),
        ),
      );
      await _markAllDirty();
    });
    _sawJournal = false;
    await syncNow();
    // The account keeps its journal on the server: go on syncing it.
    if (_sawJournal) {
      await _setState(const SyncStateTableCompanion(includeJournal: Value(true), eraseJournal: Value(false)));
    }
  }

  /// Runs a sync if sync is on (one at a time). Returns quietly if it is off
  /// or no server is set up; failures are stored in the status.
  Future<void> syncNow() => _running ??= _sync().whenComplete(() => _running = null);

  Future<void> _sync() async {
    var state = await _state();
    if (!state.enabled || !api.isConfigured) return;
    try {
      final account = await api.accountId();
      if (account != null && state.accountId != account) {
        // Another account (recovered, or the old one was revoked): start
        // over, so this device's data reaches the new account.
        await db.transaction(() async {
          if (state.accountId != null) await _markAllDirty();
          await _setState(SyncStateTableCompanion(cursor: const Value(0), accountId: Value(account)));
        });
        state = await _state();
      }
      var cursor = state.cursor;
      // Bounded, in case rows keep changing while syncing.
      for (var round = 0; round < 200; round++) {
        final out = await _collect(state);
        final response =
            await api.post('/v1/sync', {'cursor': cursor, 'changes': out.changes}) as Map<String, dynamic>;
        await db.transaction(() async {
          await out.markClean();
          await _merge((response['changes'] as Map).cast<String, dynamic>(), state.includeJournal);
          cursor = response['cursor'] as int;
          await _setState(SyncStateTableCompanion(cursor: Value(cursor)));
        });
        if (out.count == 0 && response['more'] != true) break;
      }
      if (state.eraseJournal) {
        await _setState(const SyncStateTableCompanion(eraseJournal: Value(false)));
      }
      await _setState(
        SyncStateTableCompanion(
          lastSyncAt: Value(clock().millisecondsSinceEpoch),
          lastError: const Value(null),
        ),
      );
    } on ApiException catch (e) {
      await _setState(SyncStateTableCompanion(lastError: Value(e.code)));
    }
  }

  // -- push ---------------------------------------------------------------------

  static String _iso(int? ms) =>
      ms == null ? '' : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

  static Object? _isoOrNull(int? ms) => ms == null ? null : _iso(ms);

  static int _ms(Object? iso) => DateTime.parse(iso! as String).millisecondsSinceEpoch;

  static int? _msOrNull(Object? iso) => iso == null ? null : _ms(iso);

  Future<_Outgoing> _collect(SyncStateTableData state) async {
    final out = _Outgoing();
    var room = batch;

    Future<List<D>> dirty<T extends Table, D>(TableInfo<T, D> t) async {
      if (room <= 0) return const [];
      final rows =
          await (db.select(t)
                ..where((_) => _dirty(t))
                ..limit(room))
              .get();
      room -= rows.length;
      return rows;
    }

    for (final r in await dirty(db.bookmarksTable)) {
      out.add('bookmark', {'verse_id': r.verseId, 'updated_at': _iso(r.updatedAt), 'deleted': r.deleted}, () {
        return (db.update(db.bookmarksTable)
              ..where((t) => t.verseId.equals(r.verseId) & t.updatedAt.equals(r.updatedAt)))
            .write(const BookmarksTableCompanion(dirty: Value(false)));
      });
    }
    for (final r in await dirty(db.verseStatesTable)) {
      out.add(
        'verse_state',
        {
          'verse_id': r.verseId,
          'favorite': r.favorite,
          'understood': r.understood,
          'needs_revision': r.needsRevision,
          'updated_at': _iso(r.updatedAt),
        },
        () =>
            (db.update(db.verseStatesTable)
                  ..where((t) => t.verseId.equals(r.verseId) & t.updatedAt.equals(r.updatedAt)))
                .write(const VerseStatesTableCompanion(dirty: Value(false))),
      );
    }
    for (final r in await dirty(db.highlightsTable)) {
      out.add(
        'highlight',
        {
          'id': r.id,
          'verse_id': r.verseId,
          'text_id': r.textId,
          'start': r.start,
          'end': r.end,
          'color': r.color,
          'updated_at': _iso(r.updatedAt),
          'deleted': r.deleted,
        },
        () =>
            (db.update(db.highlightsTable)..where((t) => t.id.equals(r.id) & t.updatedAt.equals(r.updatedAt)))
                .write(const HighlightsTableCompanion(dirty: Value(false))),
      );
    }
    for (final r in await dirty(db.notesTable)) {
      out.add(
        'note',
        {
          'id': r.id,
          'verse_id': r.verseId,
          'chapter': r.chapter,
          'kind': r.kind,
          'body': r.body,
          'updated_at': _iso(r.updatedAt),
          'deleted': r.deleted,
        },
        () => (db.update(db.notesTable)..where((t) => t.id.equals(r.id) & t.updatedAt.equals(r.updatedAt)))
            .write(const NotesTableCompanion(dirty: Value(false))),
      );
    }
    // Cards before their reviews: the server finds a review's card by
    // verse and card type.
    for (final r in await dirty(db.revisionItemsTable)) {
      out.add(
        'revision_item',
        {
          'verse_id': r.verseId,
          'card_type': r.cardType,
          'state': r.state,
          'step': r.step,
          'due_at': _iso(r.dueAt),
          'reps': r.reps,
          'lapses': r.lapses,
          'last_reviewed_at': _isoOrNull(r.lastReviewedAt),
          'updated_at': _iso(r.updatedAt),
          'deleted': r.deleted,
        },
        () =>
            (db.update(db.revisionItemsTable)..where(
                  (t) =>
                      t.verseId.equals(r.verseId) &
                      t.cardType.equals(r.cardType) &
                      t.updatedAt.equals(r.updatedAt),
                ))
                .write(const RevisionItemsTableCompanion(dirty: Value(false))),
      );
    }
    for (final r in await dirty(db.revisionReviewsTable)) {
      out.add(
        'revision_review',
        {
          'id': r.id,
          'verse_id': r.verseId,
          'card_type': r.cardType,
          'rating': r.rating,
          'reviewed_at': _iso(r.reviewedAt),
          'elapsed_days': r.elapsedDays,
          'scheduled_days': r.scheduledDays,
        },
        () => (db.update(
          db.revisionReviewsTable,
        )..where((t) => t.id.equals(r.id))).write(const RevisionReviewsTableCompanion(dirty: Value(false))),
      );
    }
    for (final r in await dirty(db.dailyPracticesTable)) {
      out.add(
        'daily_practice',
        {
          'date': r.date,
          'verse_id': r.verseId,
          'listened_at': _isoOrNull(r.listenedAt),
          'understood_at': _isoOrNull(r.understoodAt),
          'reflected_at': _isoOrNull(r.reflectedAt),
          'applied_at': _isoOrNull(r.appliedAt),
          // Absent = leave the server's copy alone; null = erase it.
          if (state.includeJournal) 'journal': r.journal.isEmpty ? null : r.journal,
          if (!state.includeJournal && state.eraseJournal) 'journal': null,
          'updated_at': _iso(r.updatedAt),
          'deleted': r.deleted,
        },
        () =>
            (db.update(db.dailyPracticesTable)
                  ..where((t) => t.date.equals(r.date) & t.updatedAt.equals(r.updatedAt)))
                .write(const DailyPracticesTableCompanion(dirty: Value(false))),
      );
    }
    for (final r in await dirty(db.versesReadTable)) {
      out.add(
        'verse_read',
        {
          'verse_id': r.verseId,
          'first_read_at': _iso(r.firstReadAt),
          'last_read_at': _iso(r.lastReadAt),
          'read_count': r.readCount,
        },
        () =>
            (db.update(db.versesReadTable)..where(
                  (t) =>
                      t.verseId.equals(r.verseId) &
                      t.lastReadAt.equals(r.lastReadAt) &
                      t.readCount.equals(r.readCount),
                ))
                .write(const VersesReadTableCompanion(dirty: Value(false))),
      );
    }
    for (final r in await dirty(db.readingProgressTable)) {
      out.add(
        'reading_progress',
        {'chapter': r.chapter, 'last_verse_id': r.lastVerseId, 'updated_at': _iso(r.updatedAt)},
        () =>
            (db.update(db.readingProgressTable)
                  ..where((t) => t.chapter.equals(r.chapter) & t.updatedAt.equals(r.updatedAt)))
                .write(const ReadingProgressTableCompanion(dirty: Value(false))),
      );
    }
    return out;
  }

  // -- pull ---------------------------------------------------------------------

  /// Applies the server's version unless this device has a newer unsent edit.
  Future<void> _merge(Map<String, dynamic> changes, bool includeJournal) async {
    List<Map<String, dynamic>> rows(String name) =>
        ((changes[name] as List?) ?? const []).cast<Map<String, dynamic>>();

    bool keepLocal(bool? dirty, int? localUpdated, int remoteUpdated) =>
        dirty == true && localUpdated != null && localUpdated > remoteUpdated;

    for (final r in rows('bookmark')) {
      final local = await (db.select(
        db.bookmarksTable,
      )..where((t) => t.verseId.equals(r['verse_id'] as String))).getSingleOrNull();
      final updated = _ms(r['updated_at']);
      if (keepLocal(local?.dirty, local?.updatedAt, updated)) continue;
      await db
          .into(db.bookmarksTable)
          .insertOnConflictUpdate(
            BookmarksTableCompanion.insert(
              verseId: r['verse_id'] as String,
              createdAt: local?.createdAt ?? updated,
              updatedAt: updated,
              deleted: Value(r['deleted'] as bool),
              dirty: const Value(false),
            ),
          );
    }
    for (final r in rows('verse_state')) {
      final local = await (db.select(
        db.verseStatesTable,
      )..where((t) => t.verseId.equals(r['verse_id'] as String))).getSingleOrNull();
      final updated = _ms(r['updated_at']);
      if (keepLocal(local?.dirty, local?.updatedAt, updated)) continue;
      await db
          .into(db.verseStatesTable)
          .insertOnConflictUpdate(
            VerseStatesTableCompanion.insert(
              verseId: r['verse_id'] as String,
              favorite: Value(r['favorite'] as bool),
              understood: Value(r['understood'] as bool),
              needsRevision: Value(r['needs_revision'] as bool),
              updatedAt: updated,
              dirty: const Value(false),
            ),
          );
    }
    for (final r in rows('highlight')) {
      final local = await (db.select(
        db.highlightsTable,
      )..where((t) => t.id.equals(r['id'] as String))).getSingleOrNull();
      final updated = _ms(r['updated_at']);
      if (keepLocal(local?.dirty, local?.updatedAt, updated)) continue;
      await db
          .into(db.highlightsTable)
          .insertOnConflictUpdate(
            HighlightsTableCompanion.insert(
              id: r['id'] as String,
              verseId: r['verse_id'] as String,
              textId: Value(r['text_id'] as String?),
              start: r['start'] as int,
              end: r['end'] as int,
              color: Value(r['color'] as String),
              createdAt: local?.createdAt ?? updated,
              updatedAt: updated,
              deleted: Value(r['deleted'] as bool),
              dirty: const Value(false),
            ),
          );
    }
    for (final r in rows('note')) {
      final local = await (db.select(
        db.notesTable,
      )..where((t) => t.id.equals(r['id'] as String))).getSingleOrNull();
      final updated = _ms(r['updated_at']);
      if (keepLocal(local?.dirty, local?.updatedAt, updated)) continue;
      await db
          .into(db.notesTable)
          .insertOnConflictUpdate(
            NotesTableCompanion.insert(
              id: r['id'] as String,
              verseId: Value(r['verse_id'] as String?),
              chapter: Value(r['chapter'] as int?),
              kind: Value(r['kind'] as String),
              body: r['body'] as String,
              createdAt: local?.createdAt ?? updated,
              updatedAt: updated,
              deleted: Value(r['deleted'] as bool),
              dirty: const Value(false),
            ),
          );
    }
    for (final r in rows('revision_item')) {
      final verse = r['verse_id'] as String, type = r['card_type'] as String;
      final local = await (db.select(
        db.revisionItemsTable,
      )..where((t) => t.verseId.equals(verse) & t.cardType.equals(type))).getSingleOrNull();
      final updated = _ms(r['updated_at']);
      if (keepLocal(local?.dirty, local?.updatedAt, updated)) continue;
      await db
          .into(db.revisionItemsTable)
          .insertOnConflictUpdate(
            RevisionItemsTableCompanion.insert(
              verseId: verse,
              cardType: type,
              state: Value(r['state'] as String),
              step: Value(r['step'] as int),
              dueAt: _ms(r['due_at']),
              reps: Value(r['reps'] as int),
              lapses: Value(r['lapses'] as int),
              lastReviewedAt: Value(_msOrNull(r['last_reviewed_at'])),
              createdAt: local?.createdAt ?? updated,
              updatedAt: updated,
              deleted: Value(r['deleted'] as bool),
              dirty: const Value(false),
            ),
          );
    }
    for (final r in rows('revision_review')) {
      await db
          .into(db.revisionReviewsTable)
          .insert(
            RevisionReviewsTableCompanion.insert(
              id: r['id'] as String,
              verseId: r['verse_id'] as String,
              cardType: r['card_type'] as String,
              rating: r['rating'] as int,
              reviewedAt: _ms(r['reviewed_at']),
              elapsedDays: Value((r['elapsed_days'] as num?)?.toDouble()),
              scheduledDays: Value((r['scheduled_days'] as num?)?.toDouble()),
              dirty: const Value(false),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    for (final r in rows('daily_practice')) {
      if (r['journal'] != null) _sawJournal = true;
      final date = r['date'] as String;
      final local = await (db.select(
        db.dailyPracticesTable,
      )..where((t) => t.date.equals(date))).getSingleOrNull();
      final updated = _ms(r['updated_at']);
      if (keepLocal(local?.dirty, local?.updatedAt, updated)) continue;
      await db
          .into(db.dailyPracticesTable)
          .insertOnConflictUpdate(
            DailyPracticesTableCompanion.insert(
              date: date,
              verseId: r['verse_id'] as String,
              listenedAt: Value(_msOrNull(r['listened_at'])),
              understoodAt: Value(_msOrNull(r['understood_at'])),
              reflectedAt: Value(_msOrNull(r['reflected_at'])),
              appliedAt: Value(_msOrNull(r['applied_at'])),
              journal: Value(_journal(includeJournal, local?.journal, r['journal'] as String?)),
              updatedAt: updated,
              deleted: Value(r['deleted'] as bool),
              dirty: const Value(false),
            ),
          );
    }
    for (final r in rows('verse_read')) {
      final verse = r['verse_id'] as String;
      final local = await (db.select(
        db.versesReadTable,
      )..where((t) => t.verseId.equals(verse))).getSingleOrNull();
      final first = _ms(r['first_read_at']), last = _ms(r['last_read_at']), count = r['read_count'] as int;
      final merged = (
        local == null || first < local.firstReadAt ? first : local.firstReadAt,
        local == null || last > local.lastReadAt ? last : local.lastReadAt,
        local == null || count > local.readCount ? count : local.readCount,
      );
      await db
          .into(db.versesReadTable)
          .insertOnConflictUpdate(
            VersesReadTableCompanion.insert(
              verseId: verse,
              firstReadAt: merged.$1,
              lastReadAt: merged.$2,
              readCount: Value(merged.$3),
              // Still dirty if this device knows more than the server.
              dirty: Value(merged != (first, last, count)),
            ),
          );
    }
    for (final r in rows('reading_progress')) {
      final chapter = r['chapter'] as int;
      final local = await (db.select(
        db.readingProgressTable,
      )..where((t) => t.chapter.equals(chapter))).getSingleOrNull();
      final updated = _ms(r['updated_at']);
      if (keepLocal(local?.dirty, local?.updatedAt, updated)) continue;
      await db
          .into(db.readingProgressTable)
          .insertOnConflictUpdate(
            ReadingProgressTableCompanion.insert(
              chapter: Value(chapter),
              lastVerseId: r['last_verse_id'] as String,
              updatedAt: updated,
              dirty: const Value(false),
            ),
          );
    }
  }
}

/// With journal sync on, the server's journal is taken. With it off, this
/// device's journal is its own, but an empty one is filled from the server
/// (an installation being restored).
String _journal(bool includeJournal, String? local, String? remote) {
  if (includeJournal) return remote ?? '';
  return (local ?? '').isEmpty ? (remote ?? '') : local!;
}

class _Outgoing {
  final changes = <String, List<Map<String, Object?>>>{};
  final _clean = <Future<void> Function()>[];
  int count = 0;

  void add(String collection, Map<String, Object?> record, Future<void> Function() markClean) {
    (changes[collection] ??= []).add(record);
    _clean.add(markClean);
    count++;
  }

  /// Rows that changed again while the request was in flight stay dirty
  /// (the clean-marking matches on the sent version).
  Future<void> markClean() async {
    for (final f in _clean) {
      await f();
    }
  }
}
