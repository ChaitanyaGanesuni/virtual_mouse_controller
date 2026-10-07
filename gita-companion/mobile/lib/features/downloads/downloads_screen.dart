import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/content/models.dart';
import '../../core/packs/download_manager.dart';
import '../../core/packs/offline_audio.dart';
import '../../l10n/app_localizations.dart';

/// Device TTS writes 16-bit mono WAV at about 24 kHz: ~48 kB per second,
/// unless it is compressed (AudioCompressor).
const _wavBytesPerSecond = 48000;

String formatBytes(int bytes) {
  if (bytes >= 1000 * 1000) return '${(bytes / 1e6).toStringAsFixed(bytes >= 1e8 ? 0 : 1)} MB';
  return '${(bytes / 1000).ceil()} kB';
}

String downloadError(AppLocalizations l, String? code) => switch (code) {
  'offline' => l.downloadErrorOffline,
  'no_voice' => l.downloadErrorNoVoice,
  'no_space' => l.downloadErrorNoSpace,
  'corrupt' => l.downloadErrorCorrupt,
  'interrupted' => l.downloadErrorInterrupted,
  'cancelled' => l.downloadErrorCancelled,
  _ => l.downloadErrorServer,
};

/// Settings → Downloads & storage: the content update and each chapter's
/// audio for offline listening, with their state, size and actions.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  final _estimates = <int, int>{};

  @override
  void initState() {
    super.initState();
    ref.read(downloadManagerProvider).refreshCatalog();
  }

  int _estimate(int chapter, String language) => _estimates.putIfAbsent(chapter, () {
    final m = ref.read(offlineAudioProvider).manifest(chapter, language);
    final seconds = m.chunks.fold(0.0, (s, c) => s + c.estimatedSeconds);
    final perSecond = ref.read(audioCompressorProvider)?.bytesPerSecond ?? _wavBytesPerSecond;
    return (seconds * perSecond).round();
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final language = settings.explanationLanguage;
    final overview = ref.watch(downloadsOverviewProvider(language)).value;
    final manager = ref.read(downloadManagerProvider);
    final repo = ref.watch(contentRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.downloads)),
      // Loads in milliseconds from the local database: no spinner.
      body: overview == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.storageDownloads(formatBytes(overview.downloadedBytes))),
                        const SizedBox(height: 4),
                        Text(
                          l.storageCache(formatBytes(overview.cacheBytes)),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(l.contentUpdates, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                _ContentTile(status: overview.content, catalogError: overview.catalogError, manager: manager),
                const SizedBox(height: 20),
                Text(l.offlineAudio, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(l.offlineAudioExplain, style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                for (final c in repo.chapters())
                  _AudioTile(
                    chapter: c,
                    script: settings.verseScript,
                    status: overview.audio[c.number]!,
                    estimate: _estimate(c.number, language),
                    onDownload: () => manager.downloadAudio(c.number, language),
                    onCancel: () => manager.cancel(OfflineAudio.packId(c.number, language)),
                    onRemove: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(l.removeDownloadTitle(c.number)),
                          content: Text(l.removeDownloadExplain),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text(l.remove),
                            ),
                          ],
                        ),
                      );
                      if (ok ?? false) await manager.remove(OfflineAudio.packId(c.number, language));
                    },
                  ),
              ],
            ),
    );
  }
}

class _ContentTile extends StatelessWidget {
  const _ContentTile({required this.status, required this.catalogError, required this.manager});

  final PackStatus? status;
  final String? catalogError;
  final DownloadManager manager;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = status;
    if (s == null || catalogError == 'not_configured') {
      return ListTile(contentPadding: EdgeInsets.zero, title: Text(l.contentUpdatesNeedServer));
    }
    final (String text, Widget? action) = switch (s.state) {
      PackState.updateAvailable => (
        l.contentUpdateAvailable(formatBytes(s.size ?? 0)),
        FilledButton(onPressed: manager.downloadContent, child: Text(l.download)),
      ),
      PackState.queued || PackState.downloading => (
        l.downloadingPercent(((s.progress ?? 0) * 100).round()),
        TextButton(onPressed: () => manager.cancel('content'), child: Text(l.cancel)),
      ),
      PackState.failed => (
        l.downloadFailed(downloadError(l, s.error)),
        TextButton(onPressed: manager.downloadContent, child: Text(l.retry)),
      ),
      _ when s.readyAfterRestart => (l.contentReadyAfterRestart, null),
      _ when s.needsAppUpdate => (l.contentNeedsAppUpdate, null),
      _ when catalogError == 'offline' => (l.contentCannotCheck, null),
      _ => (l.contentUpToDate, null),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(contentPadding: EdgeInsets.zero, title: Text(text), trailing: action),
        if (s.state == PackState.downloading) LinearProgressIndicator(value: s.progress),
      ],
    );
  }
}

class _AudioTile extends StatelessWidget {
  const _AudioTile({
    required this.chapter,
    required this.script,
    required this.status,
    required this.estimate,
    required this.onDownload,
    required this.onCancel,
    required this.onRemove,
  });

  final Chapter chapter;
  final VerseScript script;
  final PackStatus status;
  final int estimate;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = status;
    final subtitle = switch (s.state) {
      PackState.notDownloaded => l.aboutSize(formatBytes(estimate)),
      PackState.queued => l.queued,
      PackState.downloading => l.preparingProgress(s.done, s.total),
      PackState.downloaded => l.availableOffline(formatBytes(s.bytes)),
      PackState.updateAvailable => l.audioUpdateAvailable,
      PackState.failed => l.downloadFailed(downloadError(l, s.error)),
    };
    final action = switch (s.state) {
      PackState.notDownloaded => IconButton(
        tooltip: l.download,
        icon: const Icon(Icons.download_for_offline_outlined),
        onPressed: onDownload,
      ),
      PackState.queued || PackState.downloading => IconButton(
        tooltip: l.cancel,
        icon: const Icon(Icons.close),
        onPressed: onCancel,
      ),
      PackState.downloaded => IconButton(
        tooltip: l.remove,
        icon: const Icon(Icons.delete_outline),
        onPressed: onRemove,
      ),
      PackState.updateAvailable || PackState.failed => IconButton(
        tooltip: s.state == PackState.failed ? l.retry : l.update,
        icon: const Icon(Icons.refresh),
        onPressed: onDownload,
      ),
    };
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: s.state == PackState.downloaded
              ? Icon(
                  Icons.offline_pin,
                  color: theme.colorScheme.primary,
                  semanticLabel: l.availableOfflineShort,
                )
              : const Icon(Icons.cloud_outlined),
          title: Text(
            '${l.chapterNumber(chapter.number)} · ${chapter.nameIn(script)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(subtitle),
          trailing: action,
        ),
        if (s.state == PackState.downloading) LinearProgressIndicator(value: s.progress),
      ],
    );
  }
}
