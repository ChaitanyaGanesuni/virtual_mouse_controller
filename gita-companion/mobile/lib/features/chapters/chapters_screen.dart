import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../l10n/app_localizations.dart';

class ChaptersScreen extends ConsumerWidget {
  const ChaptersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final chapters = ref.watch(contentRepositoryProvider).chapters();
    final script = ref.watch(settingsProvider).verseScript;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.chapters)),
      body: ListView.separated(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: chapters.length,
        separatorBuilder: (_, _) => const Divider(indent: 76),
        itemBuilder: (context, i) {
          final c = chapters[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.primary,
              child: Text('${c.number}'),
            ),
            title: Text(c.nameIn(script)),
            subtitle: Text('${c.titleEn} · ${l.verseCount(c.verseCount)}'),
            onTap: () => context.push('/chapters/${c.number}'),
          );
        },
      ),
    );
  }
}
