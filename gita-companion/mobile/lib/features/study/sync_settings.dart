import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../l10n/app_localizations.dart';

/// Settings → Account & sync: turn sync on, include the journal or not,
/// get a recovery code, or restore this installation from one.
class SyncSettingsSection extends ConsumerWidget {
  const SyncSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final configured = ref.watch(serverAddressProvider).isNotEmpty;
    final status = ref.watch(syncStatusProvider).value;
    final sync = ref.read(syncServiceProvider);
    final enabled = status?.enabled ?? false;

    String statusText() {
      if (status == null) return '';
      if (status.lastError != null) return l.syncFailed(_errorText(l, status.lastError!));
      if (status.lastSyncAt == null) return status.pending > 0 ? l.syncPending(status.pending) : '';
      final at = MaterialLocalizations.of(context).formatShortDate(status.lastSyncAt!);
      final time = TimeOfDay.fromDateTime(status.lastSyncAt!).format(context);
      return status.pending > 0
          ? '${l.syncLast(at, time)} · ${l.syncPending(status.pending)}'
          : l.syncLast(at, time);
    }

    if (!configured) {
      return ListTile(title: Text(l.syncTitle), subtitle: Text(l.syncNeedsServer));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(l.syncExplain, style: theme.textTheme.bodySmall),
        ),
        SwitchListTile(
          title: Text(l.syncTitle),
          subtitle: enabled && statusText().isNotEmpty ? Text(statusText()) : null,
          value: enabled,
          onChanged: (on) async {
            await sync.setEnabled(on);
            if (on) {
              await sync.syncNow();
              final ok = (await sync.status()).lastError == null;
              if (ok && context.mounted) await _offerRecoveryCode(context, ref);
            }
          },
        ),
        SwitchListTile(
          title: Text(l.syncJournal),
          subtitle: Text(l.syncJournalHint),
          value: status?.includeJournal ?? false,
          onChanged: enabled
              ? (on) async {
                  await sync.setIncludeJournal(on);
                  await sync.syncNow();
                }
              : null,
        ),
        if (enabled)
          ListTile(leading: const Icon(Icons.sync), title: Text(l.syncNow), onTap: () => sync.syncNow()),
        if (enabled)
          ListTile(
            leading: const Icon(Icons.key),
            title: Text(l.recoveryCodeShow),
            subtitle: Text(l.recoveryCodeShowHint),
            onTap: () => _showNewCode(context, ref),
          ),
        ListTile(
          leading: const Icon(Icons.restore),
          title: Text(l.recoveryRestore),
          subtitle: Text(l.recoveryRestoreHint),
          onTap: () => _restore(context, ref),
        ),
      ],
    );
  }

  static String _errorText(AppLocalizations l, String code) => switch (code) {
    'offline' || 'timeout' => l.syncErrorOffline,
    'unauthorized' => l.syncErrorSignedOut,
    _ => l.syncErrorServer,
  };

  Future<void> _offerRecoveryCode(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.recoveryCodeOfferTitle),
        content: Text(l.recoveryCodeOffer),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.later)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.recoveryCodeShow)),
        ],
      ),
    );
    if (yes == true && context.mounted) await _showNewCode(context, ref);
  }

  Future<void> _showNewCode(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    String code;
    try {
      code = await ref.read(syncServiceProvider).createRecoveryCode();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.syncFailed(_errorText(l, e.code)))));
      }
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.recoveryCodeTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              code,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 18, letterSpacing: 1),
            ),
            const SizedBox(height: 12),
            Text(l.recoveryCodeWarning),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: code)),
            child: Text(l.copy),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(l.recoveryCodeSaved)),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final code = await showDialog<String>(context: context, builder: (_) => const _RestoreDialog());
    if (code == null || code.isEmpty) return;
    String message;
    try {
      await ref.read(syncServiceProvider).restore(code);
      message = l.recoveryRestored;
    } on ApiException catch (e) {
      message = e.code == 'unauthorized' ? l.recoveryCodeWrong : l.syncFailed(_errorText(l, e.code));
    }
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Asks for the recovery code. Owns its text controller, so it lives as
/// long as the dialog (including its closing animation).
class _RestoreDialog extends StatefulWidget {
  const _RestoreDialog();

  @override
  State<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<_RestoreDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.recoveryRestore),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.recoveryRestoreExplain),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(onPressed: () => Navigator.pop(context, _code.text.trim()), child: Text(l.restore)),
      ],
    );
  }
}
