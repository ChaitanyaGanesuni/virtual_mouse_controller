import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/audio/manifest.dart';
import '../../core/audio/playback_controller.dart';
import '../../l10n/app_localizations.dart';
import 'mini_player.dart' show playerScreenOpen;

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Human-readable message for a player error code, or null.
String? playerErrorText(AppLocalizations l, String? error) {
  if (error == null) return null;
  if (error.startsWith('no-voice:')) {
    final lang = error.substring('no-voice:'.length);
    final name = switch (lang) {
      'te' => l.languageTelugu,
      'sa' => l.languageSanskrit,
      _ => l.languageEnglish,
    };
    return l.noVoice(name);
  }
  if (error.startsWith('chunk-failed:')) return l.chunkFailed;
  return error;
}

String sectionName(AppLocalizations l, AudioChunk chunk) =>
    chunk.kind == ChunkKind.recitation ? l.sectionRecitation : l.sectionExplanation;

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => playerScreenOpen.value = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) => playerScreenOpen.value = false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playbackControllerProvider);
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) => _PlayerView(player: player),
    );
  }
}

class _PlayerView extends StatefulWidget {
  const _PlayerView({required this.player});

  final PlaybackController player;

  @override
  State<_PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<_PlayerView> {
  double? _dragging; // seconds while the user drags the slider

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final player = widget.player;
    final s = player.state;
    final chunk = s.chunk;

    if (s.manifest == null || chunk == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    final total = s.total.inMilliseconds / 1000;
    final elapsed = (_dragging ?? s.elapsed.inMilliseconds / 1000).clamp(0.0, total <= 0 ? 0.0 : total);
    final error = playerErrorText(l, s.error);
    final isSanskrit = chunk.language == 'sa';

    return Scaffold(
      appBar: AppBar(
        title: Text(l.nowPlaying),
        actions: [
          IconButton(
            tooltip: l.closePlayer,
            icon: const Icon(Icons.close),
            onPressed: () async {
              await player.stop();
              if (context.mounted && context.canPop()) context.pop();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            if (chunk.verseId != null) Text(l.verseRef(chunk.verseId!), style: theme.textTheme.headlineSmall),
            Text(
              [
                if (s.manifest!.chapter != null) l.chapterNumber(s.manifest!.chapter!),
                sectionName(l, chunk),
                if (s.manifest!.repeat > 1) l.repetitionOf(s.round, s.manifest!.repeat),
              ].join(' · '),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 20),
            // What is being read right now, so the listener can follow along.
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                chunk.displayText,
                textAlign: isSanskrit ? TextAlign.center : TextAlign.start,
                style: isSanskrit
                    ? const TextStyle(fontFamily: 'NotoSerifDevanagari', fontSize: 22, height: 1.8)
                    : theme.textTheme.bodyLarge?.copyWith(height: 1.6),
              ),
            ),
            if (s.approximate && isSanskrit) ...[
              const SizedBox(height: 12),
              _Banner(text: l.approximateSanskrit, icon: Icons.record_voice_over_outlined),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              _Banner(text: error, icon: Icons.error_outline),
            ],
            const SizedBox(height: 20),
            Slider(
              value: elapsed,
              max: total <= 0 ? 1 : total,
              onChanged: total <= 0 ? null : (v) => setState(() => _dragging = v),
              onChangeEnd: (v) async {
                await player.seekTo(Duration(milliseconds: (v * 1000).round()));
                if (mounted) setState(() => _dragging = null);
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Text(
                    formatDuration(Duration(milliseconds: (elapsed * 1000).round())),
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Text('-${formatDuration(s.remaining)}', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: l.previousVerseAudio,
                  icon: const Icon(Icons.skip_previous),
                  onPressed: player.previousVerse,
                ),
                IconButton(
                  tooltip: l.skipBack,
                  icon: const Icon(Icons.replay_10),
                  onPressed: () => player.skip(const Duration(seconds: -15)),
                ),
                IconButton.filled(
                  iconSize: 40,
                  tooltip: s.status == PlayerStatus.playing ? l.pause : l.play,
                  icon: s.status == PlayerStatus.loading
                      ? const SizedBox.square(dimension: 40, child: CircularProgressIndicator(strokeWidth: 3))
                      : Icon(s.status == PlayerStatus.playing ? Icons.pause : Icons.play_arrow),
                  onPressed: s.status == PlayerStatus.loading ? null : player.togglePlay,
                ),
                IconButton(
                  tooltip: l.skipForward,
                  icon: const Icon(Icons.forward_10),
                  onPressed: () => player.skip(const Duration(seconds: 15)),
                ),
                IconButton(
                  tooltip: l.nextVerseAudio,
                  icon: const Icon(Icons.skip_next),
                  onPressed: player.nextVerse,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(l.speed, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final speed in playbackSpeeds)
                  ChoiceChip(
                    label: Text('${speed}x'.replaceAll('.0x', 'x')),
                    selected: s.speed == speed,
                    onSelected: (_) => player.setSpeed(speed),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface)),
          ),
        ],
      ),
    );
  }
}
