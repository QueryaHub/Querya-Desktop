import 'dart:async';

import 'package:querya_desktop/core/actions/querya_command.dart';
import 'package:querya_desktop/core/actions/querya_command_host.dart';
import 'package:querya_desktop/core/actions/querya_command_registry.dart';
import 'package:querya_desktop/core/extensions/extension_command_target.dart';
import 'package:querya_desktop/core/extensions/extension_driver_session.dart';
import 'package:querya_desktop/core/extensions/models/extension_contributions.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/rpc/json_rpc_stdio_client.dart';
import 'package:querya_desktop/core/extensions/rpc/plugin_rpc_exceptions.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/extensions/extension_connection_picker_dialog.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Pushes [ExtensionManifest.contributedCommands] into [QueryaCommandRegistry].
class ExtensionCommandSync {
  ExtensionCommandSync._();

  static final ExtensionCommandSync instance = ExtensionCommandSync._();

  final Set<String> _disabledIds = {};
  List<ExtensionManifest> _lastManifests = const [];

  /// Test/DI override. Receives extension id, command id, and host context.
  Future<void> Function(
    ExtensionManifest manifest,
    CommandContribution command,
    BuildContext context,
  )? invokeOverride;

  /// Test override for toasts (palette is already closed).
  void Function(String message)? toastOverride;

  /// Test/DI override for the ambiguous-target connection picker. Returns
  /// the chosen connection id, or null if the user cancelled.
  Future<int?> Function(
    ExtensionManifest manifest,
    CommandContribution command,
    List<ConnectionRow> candidates,
    BuildContext context,
  )? pickerOverride;

  /// Test/DI override for target resolution — bypasses the live-session
  /// lookup (which needs a real driver process to populate) so the
  /// none/ambiguous/ready branches of [_invoke] can each be exercised
  /// deterministically. Defaults to [ExtensionDriverSession.targetForExtension].
  ExtensionCommandTarget Function(
    String extensionId, {
    int? preferredConnectionId,
  })? targetOverride;

  /// Test/DI override for the ambiguous-branch candidate id list. Defaults
  /// to [ExtensionDriverSession.liveConnectionIdsForExtension].
  List<int> Function(String extensionId)? liveConnectionIdsOverride;

  bool isEnabled(String extensionId) => !_disabledIds.contains(extensionId);

  /// Disables (or re-enables) an installed extension's palette commands.
  void setEnabled(String extensionId, bool enabled) {
    if (enabled) {
      _disabledIds.remove(extensionId);
    } else {
      _disabledIds.add(extensionId);
    }
    sync(_lastManifests);
  }

  /// Replaces all extension-sourced commands with those from [manifests].
  void sync(Iterable<ExtensionManifest> manifests) {
    _lastManifests = List<ExtensionManifest>.from(manifests);
    final registry = QueryaCommandRegistry.instance;
    registry.ensureCoreDefaults();
    registry.unregisterWhere((command) => command.sourceExtensionId != null);
    registry.restoreMissingCoreCommands();

    for (final manifest in manifests) {
      if (!isEnabled(manifest.id)) continue;
      for (final contribution in manifest.contributedCommands) {
        if (!isAllowedExtensionCommandId(contribution.id)) continue;
        registry.register(
          QueryaCommand(
            id: contribution.id,
            title: contribution.title,
            category: contribution.category ?? manifest.name,
            aliases: contribution.aliases,
            sourceExtensionId: manifest.id,
            execute: (context) => unawaited(
              _invoke(manifest, contribution, context),
            ),
          ),
        );
      }
    }
  }

  Future<void> _invoke(
    ExtensionManifest manifest,
    CommandContribution command,
    BuildContext context,
  ) async {
    try {
      final override = invokeOverride;
      if (override != null) {
        await override(manifest, command, context);
        return;
      }

      final preferred =
          QueryaCommandHost.maybeOf(context)?.selectedConnectionId;
      final session = ExtensionDriverSession.instance;
      final resolveTarget = targetOverride ?? session.targetForExtension;
      final target = resolveTarget(
        manifest.id,
        preferredConnectionId: preferred,
      );

      switch (target.kind) {
        case ExtensionCommandTargetKind.none:
          _toast(
            context,
            'Connect a ${manifest.name} session to run “${command.title}”.',
            variant: AppToastVariant.info,
          );
          return;
        case ExtensionCommandTargetKind.ambiguous:
          final connectionId = await _pickAmbiguousTarget(
            manifest,
            command,
            session,
            context,
          );
          if (connectionId == null) return;
          if (!context.mounted) return;
          await _executeOn(session, manifest, command, connectionId, context);
        case ExtensionCommandTargetKind.ready:
          await _executeOn(
            session,
            manifest,
            command,
            target.connectionId!,
            context,
          );
      }
    } catch (error) {
      if (!context.mounted) return;
      _toast(context, _messageFor(command, error));
    }
  }

  /// Resolves an [ExtensionCommandTargetKind.ambiguous] target: shows a
  /// connection picker over the live sessions for [manifest.id] and returns
  /// the chosen connection id, or null if the user cancelled (#892).
  Future<int?> _pickAmbiguousTarget(
    ExtensionManifest manifest,
    CommandContribution command,
    ExtensionDriverSession session,
    BuildContext context,
  ) async {
    final resolveIds =
        liveConnectionIdsOverride ?? session.liveConnectionIdsForExtension;
    final ids = resolveIds(manifest.id);
    final candidates = [
      for (final id in ids) await LocalDb.instance.getConnectionById(id),
    ].whereType<ConnectionRow>().toList();

    if (!context.mounted) return null;
    final override = pickerOverride;
    if (override != null) {
      return override(manifest, command, candidates, context);
    }

    if (candidates.isEmpty) return null;
    return showExtensionConnectionPickerDialog(
      context: context,
      extensionName: manifest.name,
      commandTitle: command.title,
      connections: candidates,
    );
  }

  Future<void> _executeOn(
    ExtensionDriverSession session,
    ExtensionManifest manifest,
    CommandContribution command,
    int connectionId,
    BuildContext context,
  ) async {
    final bridge = session.activeBridgeForExtension(
      manifest.id,
      preferredConnectionId: connectionId,
    );
    if (bridge == null) {
      _toast(
        context,
        'Connect a ${manifest.name} session to run “${command.title}”.',
        variant: AppToastVariant.info,
      );
      return;
    }
    await bridge.sendRequest('commands.execute', {
      'id': command.id,
      'commandId': command.id,
      'connectionId': connectionId,
    });
  }

  void _toast(
    BuildContext context,
    String message, {
    AppToastVariant variant = AppToastVariant.error,
  }) {
    final override = toastOverride;
    if (override != null) {
      override(message);
      return;
    }
    if (!context.mounted) return;
    showAppToast(
      context: context,
      message: message,
      variant: variant,
    );
  }

  static String _messageFor(CommandContribution command, Object error) {
    if (error is PluginProtocolTimeoutException) {
      return '“${command.title}” timed out.';
    }
    if (error is PluginCrashedException || error is PluginDeadlockException) {
      return 'The extension plugin crashed while running “${command.title}”.';
    }
    if (error is JsonRpcException) {
      return '“${command.title}” failed: ${error.message}';
    }
    return 'Could not run “${command.title}”.';
  }

  @visibleForTesting
  void resetForTest() {
    _disabledIds.clear();
    _lastManifests = const [];
    invokeOverride = null;
    toastOverride = null;
    pickerOverride = null;
    targetOverride = null;
    liveConnectionIdsOverride = null;
    QueryaCommandRegistry.instance
        .unregisterWhere((command) => command.sourceExtensionId != null);
  }
}
