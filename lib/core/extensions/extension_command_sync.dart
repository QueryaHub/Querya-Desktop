import 'dart:async';

import 'package:querya_desktop/core/actions/querya_command.dart';
import 'package:querya_desktop/core/actions/querya_command_registry.dart';
import 'package:querya_desktop/core/extensions/extension_driver_session.dart';
import 'package:querya_desktop/core/extensions/models/extension_contributions.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
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

    for (final manifest in manifests) {
      if (!isEnabled(manifest.id)) continue;
      for (final contribution in manifest.contributedCommands) {
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
    final override = invokeOverride;
    if (override != null) {
      await override(manifest, command, context);
      return;
    }

    final live = ExtensionDriverSession.instance
        .activeBridgeForExtension(manifest.id);
    if (live != null) {
      await live.sendRequest('commands.execute', {
        'id': command.id,
        'commandId': command.id,
      });
      return;
    }

    if (!context.mounted) return;
    showAppToast(
      context: context,
      message: 'Connect a ${manifest.name} session to run “${command.title}”.',
    );
  }

  @visibleForTesting
  void resetForTest() {
    _disabledIds.clear();
    _lastManifests = const [];
    invokeOverride = null;
    QueryaCommandRegistry.instance
        .unregisterWhere((command) => command.sourceExtensionId != null);
  }
}
