import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/security/safe_mode.dart';
import 'package:querya_desktop/core/theme/querya_theme_scope.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Asks the user to type the connection name before a Production connection
/// is made writable. Resolves to `true` only after a matching confirmation.
Future<bool> showSafeModeUnlockDialog({
  required material.BuildContext context,
  required String connectionName,
}) async {
  final result = await showAppDialog<bool>(
    context: context,
    builder: (_) => SafeModeUnlockDialog(connectionName: connectionName),
  );
  return result == true;
}

class SafeModeUnlockDialog extends material.StatefulWidget {
  const SafeModeUnlockDialog({super.key, required this.connectionName});

  final String connectionName;

  @override
  material.State<SafeModeUnlockDialog> createState() =>
      _SafeModeUnlockDialogState();
}

class _SafeModeUnlockDialogState extends material.State<SafeModeUnlockDialog> {
  final _controller = material.TextEditingController();

  bool get _valid =>
      isSafeModeConfirmationValid(_controller.text, widget.connectionName);

  void _confirm() {
    if (_valid) material.Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final phrase = safeModeConfirmationPhrase(widget.connectionName);
    final minutes = kSafeModeUnlockDuration.inMinutes;
    return QueryaModalDialog(
      title: const Text('Unlock Production connection'),
      description: Text(
        '"${widget.connectionName}" is tagged Production and is read-only. '
        'Unlocking allows data and schema changes for $minutes minutes, then '
        'it locks again.',
      ),
      icon: const material.Icon(material.Icons.lock_open_rounded),
      iconColor: context.workbench.destructive,
      content: material.Column(
        mainAxisSize: material.MainAxisSize.min,
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          Text('Type $phrase to confirm').small().muted(),
          const Gap(8),
          TextField(
            key: const material.Key('safe_mode_unlock_field'),
            controller: _controller,
            autofocus: true,
            placeholder: Text(phrase),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ),
      actions: [
        OutlineButton(
          onPressed: () => material.Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        DestructiveButton(
          key: const material.Key('safe_mode_unlock_confirm'),
          onPressed: _valid ? _confirm : null,
          child: Text('Unlock for $minutes minutes'),
        ),
      ],
    );
  }
}
