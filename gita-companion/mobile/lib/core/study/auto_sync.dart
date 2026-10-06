import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';

import '../db/user_database.dart';
import 'sync_service.dart';

/// Syncs when the app starts or comes back to the foreground, and a little
/// while after study data changes. Does nothing while sync is off (no
/// timers, no network).
class AutoSync with WidgetsBindingObserver {
  AutoSync(this.db, this.sync, {this.delay = const Duration(seconds: 20)});

  final UserDatabase db;
  final SyncService sync;
  final Duration delay;
  StreamSubscription<Set<TableUpdate>>? _changes;
  Timer? _timer;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _changes = db
        .tableUpdates(
          TableUpdateQuery.onAllTables([
            db.bookmarksTable,
            db.verseStatesTable,
            db.highlightsTable,
            db.notesTable,
            db.revisionItemsTable,
            db.dailyPracticesTable,
            db.readingProgressTable,
          ]),
        )
        .listen((_) => _soon());
    _ifEnabled(sync.syncNow);
  }

  Future<void> _ifEnabled(Future<void> Function() action) async {
    final state = await db.select(db.syncStateTable).getSingleOrNull();
    if (state?.enabled ?? false) await action();
  }

  void _soon() => _ifEnabled(() async {
    _timer?.cancel();
    _timer = Timer(delay, sync.syncNow);
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _ifEnabled(sync.syncNow);
    if (state == AppLifecycleState.paused) {
      // Send pending changes before the app may be stopped.
      _timer?.cancel();
      _ifEnabled(sync.syncNow);
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _changes?.cancel();
    _timer?.cancel();
  }
}
