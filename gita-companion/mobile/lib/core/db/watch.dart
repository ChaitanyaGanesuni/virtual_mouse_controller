import 'dart:async';

import 'package:drift/drift.dart';

/// Emits [load] now and again whenever one of [tables] changes. Reloads
/// run one after another, so a slow older result never replaces a newer.
Stream<T> watchTables<T>(
  GeneratedDatabase db,
  List<TableInfo<Table, dynamic>> tables,
  Future<T> Function() load,
) {
  late final StreamController<T> out;
  StreamSubscription<Set<TableUpdate>>? updates;
  var chain = Future<void>.value();
  void reload() {
    chain = chain.then((_) async {
      try {
        final value = await load();
        if (!out.isClosed) out.add(value);
      } catch (e, st) {
        if (!out.isClosed) out.addError(e, st);
      }
    });
  }

  out = StreamController<T>(
    onListen: () {
      reload();
      updates = db.tableUpdates(TableUpdateQuery.onAllTables(tables)).listen((_) => reload());
    },
    // Not awaited: drift's update stream may not finish cancelling until
    // the database closes.
    onCancel: () {
      updates?.cancel();
    },
  );
  return out.stream;
}
