import 'dart:async' show unawaited;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/extensions/extension_paths.dart';
import 'package:querya_desktop/core/extensions/local_extension_installer.dart';
import 'package:querya_desktop/core/market/marketplace_repository.dart';
import 'package:querya_desktop/core/platform/open_directory.dart';
import 'package:querya_desktop/features/settings/preferences_controls.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Preferences section for sideloading extensions from local archives (#316).
class PreferencesExtensionsSection extends material.StatefulWidget {
  const PreferencesExtensionsSection({
    super.key,
    this.installer,
    this.filePicker,
  });

  final LocalExtensionInstaller? installer;

  /// Injectable picker for tests.
  final Future<XFile?> Function()? filePicker;

  @override
  material.State<PreferencesExtensionsSection> createState() =>
      PreferencesExtensionsSectionState();
}

class PreferencesExtensionsSectionState
    extends material.State<PreferencesExtensionsSection> {
  bool _installing = false;
  bool _openingFolder = false;
  String? _error;
  String? _success;

  LocalExtensionInstaller get _installer =>
      widget.installer ?? LocalExtensionInstaller();

  Future<void> _installFromFile() async {
    setState(() {
      _installing = true;
      _error = null;
      _success = null;
    });
    try {
      final picker = widget.filePicker ??
          () => openFile(
                acceptedTypeGroups: const [
                  XTypeGroup(
                    label: 'Querya extension',
                    extensions: ['zip', 'qext'],
                  ),
                ],
              );
      final file = await picker();
      if (file == null) return;
      final path = file.path;
      if (path.isEmpty) return;

      final manifest = await _installer.installFromPath(path);
      if (!mounted) return;
      setState(() {
        _success =
            'Installed "${manifest.name}" (${manifest.id}) v${manifest.version}.';
      });
    } on MarketplaceException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to install extension: $e');
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<void> _openExtensionsFolder() async {
    setState(() {
      _openingFolder = true;
      _error = null;
    });
    try {
      final dir = await ExtensionPaths.ensureExtensionsDirectory();
      final opened = await openDirectoryInFileManager(dir.path);
      if (!mounted) return;
      if (!opened) {
        setState(() => _error = 'Could not open extensions folder.');
      }
    } finally {
      if (mounted) setState(() => _openingFolder = false);
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final busy = _installing || _openingFolder;
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        const Text('Extensions').semiBold().small().foreground(),
        const material.SizedBox(height: 8),
        const PreferencesHint(
          'Install a local .zip or .qext package without the Marketplace. '
          'Useful for development and offline environments.',
        ),
        const material.SizedBox(height: 12),
        material.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlineButton(
              onPressed: busy ? null : () => unawaited(_installFromFile()),
              child: Text(_installing ? 'Installing…' : 'Install from file…'),
            ),
            OutlineButton(
              onPressed: busy ? null : () => unawaited(_openExtensionsFolder()),
              child: Text(
                _openingFolder ? 'Opening…' : 'Open extensions folder',
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const material.SizedBox(height: 10),
          Text(_error!).small().foreground(),
        ],
        if (_success != null) ...[
          const material.SizedBox(height: 10),
          Text(_success!).muted().small(),
        ],
      ],
    );
  }
}
