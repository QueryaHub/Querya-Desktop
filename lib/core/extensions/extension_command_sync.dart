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
      final target = session.targetForExtension(
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
          _toast(
            context,
            'Select a ${manifest.name} connection to run “${command.title}”.',
            variant: AppToastVariant.info,
          );
          return;
        case ExtensionCommandTargetKind.ready:
          final bridge = session.activeBridgeForExtension(
            manifest.id,
            preferredConnectionId: target.connectionId,
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
            'connectionId': target.connectionId,
          });
      }
    } catch (error) {
      if (!context.mounted) return;
      _toast(context, _messageFor(command, error));
    }
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
    QueryaCommandRegistry.instance
        .unregisterWhere((command) => command.sourceExtensionId != null);
  }
}
