import 'dart:async';

import 'package:drift/drift.dart';

import '../audio/synthesizer.dart';
import '../db/user_database.dart';
import 'content_updates.dart';
import 'downloader.dart';
import 'offline_audio.dart';
import 'pack_catalog.dart';

enum PackState { notDownloaded, queued, downloading, downloaded, failed, updateAvailable }

class PackStatus {
  const PackStatus({
    required this.id,
    required this.state,
    this.done = 0,
    this.total = 0,
    this.bytes = 0,
    this.size,
    this.error,
    this.readyAfterRestart = false,
    this.needsAppUpdate = false,
  });

  final String id;
  final PackState state;
  final int done;
  final int total;

  /// On disk now.
  final int bytes;

  /// To download (content: from the catalog).
  final int? size;

  /// 'offline', 'server_error', 'corrupt', 'no_space', 'no_voice', 'interrupted', …
  final String? error;
  final bool readyAfterRestart;
  final bool needsAppUpdate;

  double? get progress => total > 0 ? done / total : null;
}

/// What the Downloads screen shows.
class DownloadsOverview {
  const DownloadsOverview({
    required this.content,
    required this.audio,
    required this.catalogError,
    required this.downloadedBytes,
    required this.cacheBytes,
  });

  /// Null when there is no server to update from.
  final PackStatus? content;

  /// Chapter number → status of its audio in the requested language.
  final Map<int, PackStatus> audio;

  /// Why the catalog could not be read ('offline', 'not_configured', …).
  final String? catalogError;
  final int downloadedBytes;

  /// The whole audio cache (downloads plus audio played recently).
  final int cacheBytes;
}

/// Runs downloads one at a time, remembers their state in the database
/// (so the Downloads screen survives restarts), and reports progress.
class DownloadManager {
  DownloadManager({
    required this.db,
    required this.catalogClient,
    required this.offlineAudio,
    this.contentUpdates,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final UserDatabase db;
  final PackCatalogClient catalogClient;
  final OfflineAudio offlineAudio;

  /// Null when content updates are not possible (tests, no storage).
  final ContentUpdates? contentUpdates;
  final DateTime Function() clock;

  final _changes = StreamController<void>.broadcast();
  final _queue = <String>[];
  final _cancel = <String, CancelToken>{};
  List<PackInfo>? _catalog;
  String? _catalogError;
  Future<void>? _worker;
  bool _initialised = false;

  Stream<void> get changes => _changes.stream;
  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// A download running when the app stopped is reported as interrupted;
  /// starting it again resumes it.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    await (db.update(db.offlinePacksTable)..where((t) => t.state.isIn(['queued', 'downloading']))).write(
      const OfflinePacksTableCompanion(state: Value('failed'), error: Value('interrupted')),
    );
  }

  Future<void> refreshCatalog() async {
    try {
      _catalog = await catalogClient.fetch();
      _catalogError = null;
    } on CatalogUnavailable catch (e) {
      _catalogError = e.reason;
    }
    _notify();
  }

  PackInfo? get _contentPack => _catalog?.where((p) => p.kind == 'content').firstOrNull;

  Future<OfflinePacksTableData?> _row(String id) =>
      (db.select(db.offlinePacksTable)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> _save(
    String id,
    String kind,
    String state, {
    int? done,
    int? total,
    int? bytes,
    String? fingerprint,
    String? error,
  }) async {
    await db
        .into(db.offlinePacksTable)
        .insert(
          OfflinePacksTableCompanion.insert(
            id: id,
            kind: kind,
            state: state,
            done: Value(done ?? 0),
            total: Value(total ?? 0),
            bytes: Value(bytes ?? 0),
            fingerprint: Value(fingerprint ?? ''),
            error: Value(error),
            updatedAt: clock().millisecondsSinceEpoch,
          ),
          onConflict: DoUpdate(
            (_) => OfflinePacksTableCompanion(
              state: Value(state),
              done: done == null ? const Value.absent() : Value(done),
              total: total == null ? const Value.absent() : Value(total),
              bytes: bytes == null ? const Value.absent() : Value(bytes),
              fingerprint: fingerprint == null ? const Value.absent() : Value(fingerprint),
              error: Value(error),
              updatedAt: Value(clock().millisecondsSinceEpoch),
            ),
          ),
        );
    _notify();
  }

  // -- status --------------------------------------------------------------------

  Future<PackStatus?> contentStatus() async {
    final updates = contentUpdates;
    if (updates == null) return null;
    final row = await _row('content');
    final pack = _contentPack;
    if (row != null && (row.state == 'queued' || row.state == 'downloading' || row.state == 'failed')) {
      return PackStatus(
        id: 'content',
        state: row.state == 'failed' ? PackState.failed : _state(row.state),
        done: row.done,
        total: row.total,
        size: pack?.size,
        error: row.error,
      );
    }
    if (pack == null) {
      // No catalog (offline): report what is known locally.
      return PackStatus(
        id: 'content',
        state: PackState.downloaded,
        readyAfterRestart:
            updates.pendingHash() != null && updates.pendingHash() != updates.installed.contentHash,
      );
    }
    return switch (updates.check(pack)) {
      ContentUpdateState.upToDate => const PackStatus(id: 'content', state: PackState.downloaded),
      ContentUpdateState.readyAfterRestart => const PackStatus(
        id: 'content',
        state: PackState.downloaded,
        readyAfterRestart: true,
      ),
      ContentUpdateState.needsAppUpdate => const PackStatus(
        id: 'content',
        state: PackState.downloaded,
        needsAppUpdate: true,
      ),
      ContentUpdateState.updateAvailable => PackStatus(
        id: 'content',
        state: PackState.updateAvailable,
        size: pack.size,
      ),
    };
  }

  static PackState _state(String s) => switch (s) {
    'queued' => PackState.queued,
    'downloading' => PackState.downloading,
    'downloaded' => PackState.downloaded,
    _ => PackState.failed,
  };

  Future<PackStatus> audioStatus(int chapter, String language) async {
    final id = OfflineAudio.packId(chapter, language);
    final row = await _row(id);
    if (row == null) return PackStatus(id: id, state: PackState.notDownloaded);
    var state = _state(row.state);
    if (state == PackState.downloaded) {
      final current = OfflineAudio.fingerprint(offlineAudio.manifest(chapter, language));
      if (current != row.fingerprint || !await offlineAudio.intact(id)) state = PackState.updateAvailable;
    }
    return PackStatus(
      id: id,
      state: state,
      done: row.done,
      total: row.total,
      bytes: row.bytes,
      error: row.error,
    );
  }

  Future<DownloadsOverview> overview(String language) async {
    final audio = <int, PackStatus>{for (var c = 1; c <= 18; c++) c: await audioStatus(c, language)};
    final rows = await (db.select(db.offlinePacksTable)..where((t) => t.state.equals('downloaded'))).get();
    final cache = await offlineAudio.cache.totalBytes();
    return DownloadsOverview(
      content: await contentStatus(),
      audio: audio,
      catalogError: _catalogError,
      downloadedBytes: rows.fold(0, (n, r) => n + r.bytes),
      cacheBytes: cache,
    );
  }

  /// Emits the overview now and after every change.
  Stream<DownloadsOverview> watch(String language) {
    late final StreamController<DownloadsOverview> out;
    StreamSubscription<void>? sub;
    var chain = Future<void>.value();
    void reload() => chain = chain.then((_) async {
      final o = await overview(language);
      if (!out.isClosed) out.add(o);
    });
    out = StreamController<DownloadsOverview>(
      onListen: () {
        reload();
        sub = changes.listen((_) => reload());
      },
      onCancel: () {
        sub?.cancel();
      },
    );
    return out.stream;
  }

  // -- actions ---------------------------------------------------------------------

  Future<void> downloadContent() async {
    if (_contentPack == null || contentUpdates == null) return;
    await _enqueue('content', 'content');
  }

  Future<void> downloadAudio(int chapter, String language) =>
      _enqueue(OfflineAudio.packId(chapter, language), 'audio');

  Future<void> _enqueue(String id, String kind) async {
    if (_queue.contains(id)) return;
    _queue.add(id);
    await _save(id, kind, 'queued');
    _worker ??= _work().whenComplete(() => _worker = null);
  }

  /// Stops a running or queued download (what arrived is kept for a resume).
  Future<void> cancel(String id) async {
    _cancel[id]?.cancel();
    if (_queue.remove(id)) {
      final row = await _row(id);
      if (row != null) await _save(id, row.kind, 'failed', error: 'cancelled');
    }
  }

  Future<void> remove(String id) async {
    await cancel(id);
    if (OfflineAudio.parse(id) != null) await offlineAudio.remove(id);
    await (db.delete(db.offlinePacksTable)..where((t) => t.id.equals(id))).go();
    _notify();
  }

  /// A download is running or waiting.
  bool get busy => _worker != null;

  /// Waits until the queue is empty.
  Future<void> idle() async {
    while (_worker != null) {
      await _worker;
    }
  }

  Future<void> _work() async {
    while (_queue.isNotEmpty) {
      final id = _queue.first;
      final token = _cancel[id] = CancelToken();
      try {
        if (id == 'content') {
          await _runContent(token);
        } else {
          await _runAudio(id, token);
        }
      } on DownloadException catch (e) {
        await _save(id, id == 'content' ? 'content' : 'audio', 'failed', error: e.reason);
      } on NoVoiceAvailable {
        await _save(id, 'audio', 'failed', error: 'no_voice');
      } on Exception {
        await _save(id, id == 'content' ? 'content' : 'audio', 'failed', error: 'failed');
      } finally {
        _cancel.remove(id);
        _queue.remove(id);
      }
    }
  }

  Future<void> _runContent(CancelToken token) async {
    final pack = _contentPack!;
    await _save('content', 'content', 'downloading', done: 0, total: pack.size);
    var last = 0;
    await contentUpdates!.download(
      pack,
      cancel: token,
      onProgress: (got, total) {
        // Persist about every 5%.
        if (got - last >= total ~/ 20 || got == total) {
          last = got;
          _save('content', 'content', 'downloading', done: got, total: total);
        }
      },
    );
    await (db.delete(db.offlinePacksTable)..where((t) => t.id.equals('content'))).go();
    _notify();
  }

  Future<void> _runAudio(String id, CancelToken token) async {
    final (chapter, language) = OfflineAudio.parse(id)!;
    final fingerprint = OfflineAudio.fingerprint(offlineAudio.manifest(chapter, language));
    await _save(id, 'audio', 'downloading', done: 0);
    final bytes = await offlineAudio.download(
      chapter,
      language,
      cancel: token,
      onProgress: (done, total) => _save(id, 'audio', 'downloading', done: done, total: total),
    );
    await _save(id, 'audio', 'downloaded', bytes: bytes, fingerprint: fingerprint);
  }

  void dispose() => _changes.close();
}
