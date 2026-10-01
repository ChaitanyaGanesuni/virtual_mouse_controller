import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../l10n/app_localizations.dart';
import 'chat_screen.dart';
import 'tutor_models.dart';

/// Past conversations, stored on the server.
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  late Future<List<Conversation>> _future = _load();

  Future<List<Conversation>> _load() => ref.read(tutorApiProvider).conversations();

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
  }

  Future<void> _delete(Conversation c) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.teacherDeleteConversation),
        content: Text(c.title ?? l.teacherUntitled),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.delete)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(tutorApiProvider).deleteConversation(c.id);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tutorErrorText(l, e))));
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.teacherHistory)),
      body: FutureBuilder<List<Conversation>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.error is ApiException) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: TutorErrorCard(error: snap.error! as ApiException, onRetry: () async => _reload()),
            );
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) return Center(child: Text(l.teacherHistoryEmpty));
          final local = MaterialLocalizations.of(context);
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = items[i];
              final when = local.formatMediumDate(c.updatedAt.toLocal());
              return ListTile(
                title: Text(c.title ?? l.teacherUntitled, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text([if (c.pinnedVerseId != null) 'BG ${c.pinnedVerseId}', when].join(' · ')),
                onTap: () => context.push('/tutor?c=${c.id}'),
                trailing: IconButton(
                  tooltip: l.teacherDeleteConversation,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(c),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
