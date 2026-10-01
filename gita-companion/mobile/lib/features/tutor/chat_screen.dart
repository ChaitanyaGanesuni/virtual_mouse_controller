import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../l10n/app_localizations.dart';
import 'tutor_chat.dart';
import 'tutor_models.dart';

/// A chat with the AI teacher, optionally about one verse.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.pinnedVerseId, this.conversationId, this.explainMode});

  final String? pinnedVerseId;
  final String? conversationId;

  /// Start by explaining the pinned verse in this mode.
  final TutorMode? explainMode;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  late final TutorChat chat;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    chat = TutorChat(
      ref.read(tutorApiProvider),
      pinnedVerseId: widget.pinnedVerseId,
      conversationId: widget.conversationId,
      mode: widget.explainMode ?? (widget.pinnedVerseId != null ? TutorMode.simple : TutorMode.free),
      language: ref.read(settingsProvider).explanationLanguage,
    )..addListener(_scrollToEnd);
    if (widget.conversationId != null) chat.load();
    if (widget.explainMode != null && widget.pinnedVerseId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) chat.explain(label: AppLocalizations.of(context).explainWithTeacher);
      });
    }
  }

  @override
  void dispose() {
    chat.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final q = _input.text;
    if (q.trim().isEmpty || chat.busy) return;
    _input.clear();
    chat.ask(q);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.teacherTitle),
        actions: [
          IconButton(
            tooltip: l.teacherHistory,
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/tutor/history'),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: chat,
        builder: (context, _) => Column(
          children: [
            _Controls(chat: chat),
            const Divider(height: 1),
            Expanded(child: _messages(context, l)),
            _InputBar(controller: _input, enabled: !chat.busy, onSend: _send),
          ],
        ),
      ),
    );
  }

  Widget _messages(BuildContext context, AppLocalizations l) {
    final theme = Theme.of(context);
    final empty = chat.messages.isEmpty && chat.pending == null && !chat.loading;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (chat.loading) const Center(child: CircularProgressIndicator()),
        if (empty) ...[
          Text(
            l.teacherEmpty,
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (chat.pinnedVerseId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.auto_awesome),
                label: Text(l.explainWithTeacher),
                onPressed: () => chat.explain(label: l.explainWithTeacher),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in [l.teacherSuggestion1, l.teacherSuggestion2, l.teacherSuggestion3])
                  ActionChip(label: Text(s), onPressed: () => chat.ask(s)),
              ],
            ),
        ],
        for (final m in chat.messages)
          if (m.isAnswer) AnswerCard(message: m) else _QuestionBubble(text: m.content),
        if (chat.pending != null) _QuestionBubble(text: chat.pending!),
        if (chat.busy)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Expanded(child: Text(l.teacherThinking, style: theme.textTheme.bodySmall)),
              ],
            ),
          ),
        if (chat.error != null) TutorErrorCard(error: chat.error!, onRetry: chat.retry),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.chat});

  final TutorChat chat;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (chat.pinnedVerseId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ActionChip(
                avatar: const Icon(Icons.menu_book_outlined, size: 18),
                label: Text(l.teacherPinned(chat.pinnedVerseId!)),
                onPressed: () => context.push('/verse/${chat.pinnedVerseId}'),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final m in TutorMode.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(tutorModeName(l, m)),
                      selected: chat.mode == m,
                      onSelected: chat.busy ? null : (_) => chat.setMode(m),
                    ),
                  ),
                const SizedBox(width: 6),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'en', label: Text(l.languageEnglish)),
                    ButtonSegment(value: 'te', label: Text(l.languageTelugu)),
                  ],
                  selected: {chat.language},
                  onSelectionChanged: chat.busy ? null : (v) => chat.setLanguage(v.first),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String tutorModeName(AppLocalizations l, TutorMode m) => switch (m) {
  TutorMode.free => l.modeFree,
  TutorMode.simple => l.modeSimple,
  TutorMode.deep => l.modeDeep,
  TutorMode.practical => l.modePractical,
  TutorMode.story => l.modeStory,
  TutorMode.child => l.modeChild,
  TutorMode.sanskritTerms => l.modeTerms,
};

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.enabled, required this.onSend});

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                maxLength: 1000,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: l.teacherInputHint,
                  counterText: '',
                  border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              tooltip: l.teacherSend,
              icon: const Icon(Icons.send),
              onPressed: enabled ? onSend : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionBubble extends StatelessWidget {
  const _QuestionBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: 48, bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(text, style: theme.textTheme.bodyLarge),
      ),
    );
  }
}

/// One answer from the AI teacher. Always labelled as AI interpretation and
/// always followed by its sources, which the server has checked.
class AnswerCard extends StatelessWidget {
  const AnswerCard({super.key, required this.message});

  final TutorMessage message;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final date = MaterialLocalizations.of(context).formatMediumDate(message.createdAt.toLocal());
    final notes = [
      if (message.flags.contains('citations_removed')) l.teacherCitationsRemoved,
      if (message.flags.contains('unverified_quotes')) l.teacherUnverifiedQuotes,
    ];

    return Container(
      margin: const EdgeInsets.only(right: 8, bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(left: BorderSide(color: theme.colorScheme.tertiary, width: 3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.tertiary),
              const SizedBox(width: 6),
              Expanded(child: Text(l.aiAnswerLabel(message.model ?? '?', date), style: muted)),
            ],
          ),
          if (message.support != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.favorite_outline, color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectableText(
                      message.support!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          ...answerBody(context, message.content),
          if (message.uncertainPoints.isNotEmpty || message.confidence == 'low') ...[
            const SizedBox(height: 8),
            Text(
              message.confidence == 'low'
                  ? '${l.teacherLowConfidence} · ${l.teacherUncertain}'
                  : l.teacherUncertain,
              style: theme.textTheme.labelLarge,
            ),
            for (final u in message.uncertainPoints) _Bullet(text: u),
          ],
          if (!message.outOfScope) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.verified_outlined, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(l.teacherSources, style: theme.textTheme.labelLarge)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in message.citations)
                  ActionChip(
                    label: Text('BG ${c.verse}'),
                    tooltip: c.sourceId,
                    onPressed: () => context.push('/verse/${c.verse}'),
                  ),
              ],
            ),
          ],
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(child: Text(n, style: muted)),
                ],
              ),
            ),
          if (message.flags.contains('cached'))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(l.teacherCached, style: muted),
            ),
        ],
      ),
    );
  }
}

/// The server sends plain text: paragraphs separated by blank lines, list
/// items starting with "- ".
List<Widget> answerBody(BuildContext context, String text) {
  final style = Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55);
  final out = <Widget>[];
  for (final para in text.split(RegExp(r'\n\s*\n'))) {
    final lines = para.trim().split('\n');
    if (lines.every((x) => x.trimLeft().startsWith('- ') || x.trim().isEmpty)) {
      for (final line in lines.where((x) => x.trim().isNotEmpty)) {
        out.add(_Bullet(text: line.trimLeft().substring(2), style: style));
      }
    } else {
      out.add(SelectableText(para.trim(), style: style));
    }
    out.add(const SizedBox(height: 8));
  }
  if (out.isNotEmpty) out.removeLast();
  return out;
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('•  ', style: style),
        Expanded(child: SelectableText(text, style: style)),
      ],
    ),
  );
}

String tutorErrorText(AppLocalizations l, ApiException e) => switch (e.code) {
  'not_configured' => l.errNotConfigured,
  'offline' => l.errOffline,
  'timeout' => l.errTimeout,
  'quota_exceeded' => l.errQuota,
  'providers_busy' => l.errBusy,
  'no_verified_answer' => l.errNoVerified,
  'tutor_unavailable' => l.errUnavailable,
  _ => l.errGeneric,
};

class TutorErrorCard extends StatelessWidget {
  const TutorErrorCard({super.key, required this.error, required this.onRetry});

  final ApiException error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final canRetry = !{'not_configured', 'quota_exceeded', 'tutor_unavailable'}.contains(error.code);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tutorErrorText(l, error), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          if (error.code == 'not_configured')
            TextButton(onPressed: () => context.push('/settings'), child: Text(l.openSettings))
          else if (canRetry)
            TextButton(onPressed: onRetry, child: Text(l.tryAgain)),
        ],
      ),
    );
  }
}
