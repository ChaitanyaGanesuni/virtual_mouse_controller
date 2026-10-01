import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../core/api/server_address.dart';
import '../../l10n/app_localizations.dart';
import 'chat_screen.dart';

/// Settings → AI teacher: server address, privacy note, delete data.
class TeacherSettingsSection extends ConsumerWidget {
  const TeacherSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final chosen = ref.watch(settingsProvider).tutorServer;
    final effective = ref.watch(serverAddressProvider);
    final subtitle = chosen.isNotEmpty
        ? chosen
        : effective.isNotEmpty
        ? '${l.teacherServerBuiltIn}: $effective'
        : l.teacherServerNone;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.dns_outlined),
          title: Text(l.teacherServer),
          subtitle: Text(subtitle),
          onTap: () => _editServer(context, ref, chosen),
        ),
        Text(
          l.teacherPrivacy,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (effective.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: Text(l.teacherDeleteData),
              onPressed: () => _deleteData(context, ref),
            ),
          ),
      ],
    );
  }

  Future<void> _editServer(BuildContext context, WidgetRef ref, String current) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => ServerAddressDialog(initial: current),
    );
    if (value == null) return;
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(tutorServer: normalizeServerAddress(value)));
  }

  Future<void> _deleteData(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.teacherDeleteData),
        content: Text(l.teacherDeleteConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.delete)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(tutorApiProvider).deleteAllData();
      messenger.showSnackBar(SnackBar(content: Text(l.teacherDeleted)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tutorErrorText(l, e))));
    }
  }
}

class ServerAddressDialog extends StatefulWidget {
  const ServerAddressDialog({super.key, required this.initial});

  final String initial;

  @override
  State<ServerAddressDialog> createState() => _ServerAddressDialogState();
}

class _ServerAddressDialogState extends State<ServerAddressDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  ServerAddressProblem? _problem;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final problem = checkServerAddress(_controller.text);
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.teacherServer),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        autocorrect: false,
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          hintText: 'https://gita.example.org',
          helperText: l.teacherServerHelp,
          helperMaxLines: 3,
          errorMaxLines: 3,
          errorText: switch (_problem) {
            ServerAddressProblem.invalid => l.teacherServerInvalid,
            ServerAddressProblem.httpsRequired => l.teacherServerHttps,
            null => null,
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(onPressed: _save, child: Text(l.save)),
      ],
    );
  }
}
