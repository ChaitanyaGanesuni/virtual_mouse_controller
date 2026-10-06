import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/study/study_repository.dart';
import '../../l10n/app_localizations.dart';

Color highlightColor(BuildContext context, String name) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final base = switch (name) {
    'green' => const Color(0xFF7FB77E),
    'blue' => const Color(0xFF7FA7D9),
    'pink' => const Color(0xFFE29BB5),
    _ => const Color(0xFFE6B450),
  };
  return base.withValues(alpha: dark ? 0.35 : 0.4);
}

String noteKindLabel(AppLocalizations l, String kind) => switch (kind) {
  'question' => l.noteKindQuestion,
  'reflection' => l.noteKindReflection,
  _ => l.noteKindNote,
};

/// Bookmark, favourite, "I understand this", "revise this", and a note:
/// the user's own relation to a verse, kept on the device.
class StudyBar extends ConsumerWidget {
  const StudyBar({super.key, required this.verseId});

  final String verseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final study = ref.watch(verseStudyProvider(verseId)).value ?? const VerseStudy();
    final repo = ref.read(studyRepositoryProvider);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        IconButton(
          tooltip: study.bookmarked ? l.removeBookmark : l.addBookmark,
          isSelected: study.bookmarked,
          icon: const Icon(Icons.bookmark_border),
          selectedIcon: const Icon(Icons.bookmark),
          onPressed: () => repo.setBookmarked(verseId, !study.bookmarked),
        ),
        IconButton(
          tooltip: study.favorite ? l.removeFavorite : l.addFavorite,
          isSelected: study.favorite,
          icon: const Icon(Icons.favorite_border),
          selectedIcon: const Icon(Icons.favorite),
          onPressed: () => repo.setFavorite(verseId, !study.favorite),
        ),
        FilterChip(
          label: Text(l.understood),
          selected: study.understood,
          onSelected: (v) => repo.setUnderstood(verseId, v),
        ),
        FilterChip(
          label: Text(l.revise),
          tooltip: l.reviseHint,
          selected: study.needsRevision,
          onSelected: (v) => repo.setNeedsRevision(verseId, v),
        ),
        IconButton(
          tooltip: l.addNote,
          icon: const Icon(Icons.edit_note),
          onPressed: () => showNoteEditor(context, ref, verseId: verseId),
        ),
      ],
    );
  }
}

/// Create or edit a note, question or reflection.
Future<void> showNoteEditor(BuildContext context, WidgetRef ref, {String? verseId, StudyNote? note}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _NoteEditor(verseId: verseId, note: note),
  );
}

class _NoteEditor extends ConsumerStatefulWidget {
  const _NoteEditor({this.verseId, this.note});

  final String? verseId;
  final StudyNote? note;

  @override
  ConsumerState<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<_NoteEditor> {
  late final _text = TextEditingController(text: widget.note?.body ?? '');
  late NoteKind _kind = widget.note == null ? NoteKind.note : NoteKind.fromWire(widget.note!.kind);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    await ref
        .read(studyRepositoryProvider)
        .saveNote(id: widget.note?.id, verseId: widget.verseId, kind: _kind, body: body);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final verse = widget.verseId ?? widget.note?.verseId;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            verse == null ? l.noteGeneral : l.noteOnVerse(l.verseRef(verse)),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          SegmentedButton<NoteKind>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: NoteKind.note, label: Text(l.noteKindNote)),
              ButtonSegment(value: NoteKind.question, label: Text(l.noteKindQuestion)),
              ButtonSegment(value: NoteKind.reflection, label: Text(l.noteKindReflection)),
            ],
            selected: {_kind},
            onSelectionChanged: (v) => setState(() => _kind = v.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            maxLength: 20000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: l.noteHint, border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text(l.notePrivacy, style: Theme.of(context).textTheme.bodySmall)),
              const SizedBox(width: 12),
              FilledButton(onPressed: _save, child: Text(l.save)),
            ],
          ),
        ],
      ),
    );
  }
}

/// A note in a list, with edit and delete.
class NoteTile extends ConsumerWidget {
  const NoteTile({super.key, required this.note, this.showVerse = false});

  final StudyNote note;
  final bool showVerse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final where = note.verseId != null ? l.verseRef(note.verseId!) : l.noteGeneral;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(note.body, maxLines: 4, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        showVerse ? '${noteKindLabel(l, note.kind)} · $where' : noteKindLabel(l, note.kind),
        style: theme.textTheme.bodySmall,
      ),
      onTap: note.verseId != null && showVerse ? () => context.push('/verse/${note.verseId}') : null,
      trailing: PopupMenuButton<String>(
        tooltip: l.more,
        onSelected: (v) async {
          if (v == 'edit') await showNoteEditor(context, ref, note: note);
          if (v == 'delete') await ref.read(studyRepositoryProvider).deleteNote(note.id);
          if (v == 'ask' && context.mounted) unawaited(context.push('/tutor?verse=${note.verseId}'));
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'edit', child: Text(l.edit)),
          if (note.kind == 'question' && note.verseId != null)
            PopupMenuItem(value: 'ask', child: Text(l.askAboutVerse)),
          PopupMenuItem(value: 'delete', child: Text(l.delete)),
        ],
      ),
    );
  }
}

/// The verse's notes, under the reader's text.
class VerseNotes extends ConsumerWidget {
  const VerseNotes({super.key, required this.verseId});

  final String verseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(verseStudyProvider(verseId)).value?.notes ?? const [];
    return Column(children: [for (final n in notes) NoteTile(note: n)]);
  }
}

/// Text the user can select and highlight (long-press → "Highlight");
/// tapping a highlight offers to remove it.
class HighlightableText extends ConsumerWidget {
  const HighlightableText({
    super.key,
    required this.text,
    required this.verseId,
    required this.textId,
    this.style,
  });

  final String text;
  final String verseId;
  final String? textId;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final highlights = (ref.watch(verseStudyProvider(verseId)).value?.highlights ?? const <StudyHighlight>[])
        .where((h) => h.textId == textId && h.end <= text.length)
        .toList();
    final spans = <TextSpan>[];
    var at = 0;
    for (final h in highlights) {
      if (h.start < at) continue; // overlapping: the first one wins
      spans.add(TextSpan(text: text.substring(at, h.start)));
      spans.add(
        TextSpan(
          text: text.substring(h.start, h.end),
          style: TextStyle(backgroundColor: highlightColor(context, h.color)),
          semanticsLabel: '${l.highlighted}: ${text.substring(h.start, h.end)}',
        ),
      );
      at = h.end;
    }
    spans.add(TextSpan(text: text.substring(at)));

    return SelectableText.rich(
      TextSpan(children: spans),
      style: style,
      onTap: () {},
      contextMenuBuilder: (context, state) {
        final sel = state.textEditingValue.selection;
        final inside = highlights
            .where((h) => sel.isValid && h.start < sel.end && sel.start < h.end)
            .toList();
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: state.contextMenuAnchors,
          buttonItems: [
            if (sel.isValid && !sel.isCollapsed)
              ContextMenuButtonItem(
                label: l.highlight,
                onPressed: () {
                  ref
                      .read(studyRepositoryProvider)
                      .addHighlight(verseId: verseId, textId: textId, start: sel.start, end: sel.end);
                  state.hideToolbar();
                },
              ),
            for (final h in inside)
              ContextMenuButtonItem(
                label: l.removeHighlight,
                onPressed: () {
                  ref.read(studyRepositoryProvider).deleteHighlight(h.id);
                  state.hideToolbar();
                },
              ),
            ...state.contextMenuButtonItems,
          ],
        );
      },
    );
  }
}
