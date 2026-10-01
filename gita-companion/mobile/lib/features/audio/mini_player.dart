import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/audio/playback_controller.dart';
import '../../l10n/app_localizations.dart';
import 'player_screen.dart';

/// True while the full player screen is open (the mini player hides then).
/// Updated after frames, never during a build.
final playerScreenOpen = ValueNotifier<bool>(false);

/// Wraps every screen: when something is playing, a slim player sits at the
/// bottom on all screens (except the full player itself). The widget tree
/// keeps the same shape whether or not the bar is shown, so the app's
/// navigator is never re-parented.
class MiniPlayerShell extends ConsumerWidget {
  const MiniPlayerShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playbackControllerProvider);
    final router = ref.watch(routerProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([player, playerScreenOpen]),
      child: child,
      builder: (context, navigator) {
        final show = player.state.isActive && !playerScreenOpen.value;
        return Column(
          children: [
            // While shown, the mini player owns the bottom safe area.
            Expanded(
              child: MediaQuery.removePadding(context: context, removeBottom: show, child: navigator!),
            ),
            if (show) _MiniPlayer(player: player, onOpen: () => router.push('/player')),
          ],
        );
      },
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.player, required this.onOpen});

  final PlaybackController player;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = player.state;
    final chunk = s.chunk!;
    final progress = s.total.inMilliseconds == 0 ? 0.0 : s.elapsed.inMilliseconds / s.total.inMilliseconds;
    return Material(
      color: theme.colorScheme.surface,
      shape: Border(top: BorderSide(color: theme.colorScheme.outline)),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 2,
              backgroundColor: theme.colorScheme.primaryContainer,
            ),
            InkWell(
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
                child: Row(
                  children: [
                    Icon(Icons.graphic_eq, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            chunk.verseId == null ? l.nowPlaying : l.verseRef(chunk.verseId!),
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            '${sectionName(l, chunk)} · ${formatDuration(s.elapsed)} / ${formatDuration(s.total)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    // The bar sits above the navigator (no Overlay), so it uses
                    // semantic labels instead of tooltips.
                    Semantics(
                      button: true,
                      label: s.status == PlayerStatus.playing ? l.pause : l.play,
                      excludeSemantics: true,
                      child: IconButton(
                        icon: Icon(s.status == PlayerStatus.playing ? Icons.pause : Icons.play_arrow),
                        onPressed: s.status == PlayerStatus.loading ? null : player.togglePlay,
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: l.closePlayer,
                      excludeSemantics: true,
                      child: IconButton(icon: const Icon(Icons.close), onPressed: player.stop),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
