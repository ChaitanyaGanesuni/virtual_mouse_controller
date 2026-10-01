import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio/manifest.dart';
import '../../core/audio/playback_controller.dart';
import '../../l10n/app_localizations.dart';
import 'listen_actions.dart';
import 'player_screen.dart';

/// "Continue listening" on Home: the most recent unfinished listening
/// position, resumable after the app was closed.
class ContinueListeningCard extends ConsumerStatefulWidget {
  const ContinueListeningCard({super.key, this.header});

  /// Shown above the card only when there is something to continue.
  final Widget? header;

  @override
  ConsumerState<ContinueListeningCard> createState() => _ContinueListeningCardState();
}

class _ContinueListeningCardState extends ConsumerState<ContinueListeningCard> {
  ({AudioManifest manifest, int index})? _item;
  PlayerStatus? _lastStatus;
  late final PlaybackController _player;

  @override
  void initState() {
    super.initState();
    _player = ref.read(playbackControllerProvider);
    _player.addListener(_onPlayer);
    _load();
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayer);
    super.dispose();
  }

  void _onPlayer() {
    final status = _player.state.status;
    if (status != _lastStatus && status != PlayerStatus.playing && status != PlayerStatus.loading) _load();
    _lastStatus = status;
  }

  Future<void> _load() async {
    final saved = await ref.read(listeningProgressProvider).latest();
    final manifest = saved == null ? null : ref.read(manifestResolverProvider).resolve(saved.manifestId);
    final index = manifest?.chunks.indexWhere((c) => c.id == saved!.audioChunkId) ?? -1;
    if (!mounted) return;
    setState(() => _item = (manifest == null || index < 0) ? null : (manifest: manifest, index: index));
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    if (item == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final chunk = item.manifest.chunks[item.index];
    var done = 0.0, total = 0.0;
    for (var i = 0; i < item.manifest.chunks.length; i++) {
      final s = item.manifest.chunks[i].estimatedSeconds;
      total += s;
      if (i < item.index) done += s;
    }
    final percent = total == 0 ? 0 : (done / total * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ?widget.header,
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: const Icon(Icons.headphones),
            title: Text(
              [
                if (item.manifest.chapter != null) l.chapterNumber(item.manifest.chapter!),
                if (chunk.verseId != null) l.verseRef(chunk.verseId!),
              ].join(' · '),
            ),
            subtitle: Text('${sectionName(l, chunk)} · ${l.listeningProgress(percent)}'),
            trailing: const Icon(Icons.play_arrow),
            onTap: () => startListening(context, ref, item.manifest),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
