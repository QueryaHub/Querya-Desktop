import 'dart:async' show unawaited;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/querya_theme_preset.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:querya_desktop/core/theme/theme_import_service.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Appearance / theme controls for [PreferencesDialog].
class PreferencesAppearanceSection extends material.StatefulWidget {
  const PreferencesAppearanceSection({super.key});

  @override
  material.State<PreferencesAppearanceSection> createState() =>
      _PreferencesAppearanceSectionState();
}

class _PreferencesAppearanceSectionState
    extends material.State<PreferencesAppearanceSection> {
  final _controller = ThemeController.instance;
  String? _importError;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    await _controller.setThemeMode(mode);
  }

  Future<void> _setPreset(QueryaThemePreset preset) async {
    await _controller.setPreset(preset);
  }

  Future<void> _pickAndImportTheme() async {
    setState(() {
      _importing = true;
      _importError = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'VS Code theme',
            extensions: ['json', 'jsonc'],
          ),
        ],
      );
      if (file == null) return;
      final path = file.path;
      if (path.isEmpty) return;
      final result = await _controller.importThemeFromFile(path);
      if (!mounted) return;
      switch (result) {
        case ThemeImportSuccess():
          setState(() => _importError = null);
        case ThemeImportFailure(:final message):
          setState(() => _importError = message);
      }
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  Future<void> _resetAppearance() async {
    await _controller.resetToDefaults();
    if (mounted) setState(() => _importError = null);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final c = _controller;
    final importedLabel = c.hasImportedTheme
        ? 'Imported: ${c.importedThemeName ?? 'theme'}'
        : 'Imported theme (none)';

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        const Text('Appearance').semiBold().small(),
        const material.SizedBox(height: 8),
        material.Row(
          children: [
            const Text('Theme mode').small(),
            const material.SizedBox(width: 12),
            material.DropdownButton<ThemeMode>(
              value: c.themeMode,
              onChanged: (v) {
                if (v != null) unawaited(_setThemeMode(v));
              },
              items: const [
                material.DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: material.Text('Dark'),
                ),
                material.DropdownMenuItem(
                  value: ThemeMode.light,
                  child: material.Text('Light'),
                ),
                material.DropdownMenuItem(
                  value: ThemeMode.system,
                  child: material.Text('System'),
                ),
              ],
            ),
          ],
        ),
        const material.SizedBox(height: 12),
        material.Row(
          crossAxisAlignment: material.CrossAxisAlignment.start,
          children: [
            material.Padding(
              padding: const material.EdgeInsets.only(top: 8),
              child: const Text('Color preset').small(),
            ),
            const material.SizedBox(width: 12),
            material.Expanded(
              child: material.DropdownButton<QueryaThemePreset>(
                value: c.preset,
                isExpanded: true,
                onChanged: (v) {
                  if (v != null) unawaited(_setPreset(v));
                },
                items: [
                  const material.DropdownMenuItem(
                    value: QueryaThemePreset.queryaDark,
                    child: material.Text('Querya Dark'),
                  ),
                  const material.DropdownMenuItem(
                    value: QueryaThemePreset.queryaLight,
                    child: material.Text('Querya Light'),
                  ),
                  material.DropdownMenuItem(
                    value: QueryaThemePreset.imported,
                    enabled: c.hasImportedTheme,
                    child: material.Text(importedLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
        const material.SizedBox(height: 12),
        material.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlineButton(
              onPressed: _importing ? null : () => unawaited(_pickAndImportTheme()),
              child: material.Text(_importing ? 'Importing…' : 'Import theme…'),
            ),
            OutlineButton(
              onPressed: () => unawaited(_resetAppearance()),
              child: const Text('Reset appearance'),
            ),
          ],
        ),
        if (_importError != null) ...[
          const material.SizedBox(height: 8),
          material.Text(
            _importError!,
            style: material.TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.destructive,
            ),
          ),
        ],
        const material.SizedBox(height: 4),
        const Text(
          'Import VS Code theme JSON/JSONC (.colors subset). Changes apply immediately.',
        ).muted().xSmall(),
      ],
    );
  }
}
