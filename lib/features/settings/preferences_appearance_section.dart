import 'dart:async' show unawaited;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/ui_scale_controller.dart';
import 'package:querya_desktop/core/theme/querya_theme_preset.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:querya_desktop/core/theme/theme_import_service.dart';
import 'package:querya_desktop/features/settings/preferences_controls.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

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
  final _uiScale = UiScaleController.instance;
  String? _importError;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onThemeChanged);
    _uiScale.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onThemeChanged);
    _uiScale.removeListener(_onThemeChanged);
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

  Future<void> _setThemeAnimation(bool enabled) async {
    await _controller.setThemeAnimationEnabled(enabled);
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
        const Text('Appearance').semiBold().small().foreground(),
        const material.SizedBox(height: 8),
        PreferencesFieldRow(
          label: 'Theme mode',
          control: PreferencesDropdownMenu<ThemeMode>(
            value: c.themeMode,
            onSelected: (v) {
              if (v != null) unawaited(_setThemeMode(v));
            },
            entries: const [
              material.DropdownMenuEntry(
                value: ThemeMode.dark,
                label: 'Dark',
              ),
              material.DropdownMenuEntry(
                value: ThemeMode.light,
                label: 'Light',
              ),
              material.DropdownMenuEntry(
                value: ThemeMode.system,
                label: 'System',
              ),
            ],
          ),
        ),
        const material.SizedBox(height: 12),
        PreferencesFieldRow(
          label: 'Color preset',
          control: PreferencesDropdownMenu<QueryaThemePreset>(
            value: c.preset,
            onSelected: (v) {
              if (v != null) unawaited(_setPreset(v));
            },
            entries: [
              const material.DropdownMenuEntry(
                value: QueryaThemePreset.queryaDark,
                label: 'Querya Dark',
              ),
              const material.DropdownMenuEntry(
                value: QueryaThemePreset.queryaLight,
                label: 'Querya Light',
              ),
              material.DropdownMenuEntry(
                value: QueryaThemePreset.imported,
                enabled: c.hasImportedTheme,
                label: importedLabel,
              ),
            ],
          ),
        ),
        const material.SizedBox(height: 12),
        PreferencesFieldRow(
          label: 'Interface scale',
          hint:
              'Snap to presets (75%, 85%, 90%, 100% …). Hold Shift for 1% fine control.',
          control: InterfaceScaleSlider(scale: _uiScale.scale),
        ),
        const material.SizedBox(height: 12),
        PreferencesFieldRow(
          label: 'Animate theme changes',
          control: material.Builder(
            builder: (context) {
              final h = QueryaDropdownTokens.scaledTriggerHeight(context);
              return material.SizedBox(
                height: h,
                child: material.Align(
                  alignment: material.Alignment.centerLeft,
                  child: material.Switch(
                    value: c.themeAnimationEnabled,
                    onChanged: (v) => unawaited(_setThemeAnimation(v)),
                  ),
                ),
              );
            },
          ),
        ),
        const material.SizedBox(height: 4),
        const PreferencesHint(
          'Smooth transitions when switching dark/light or presets. Off by default for stability.',
        ),
        const material.SizedBox(height: 12),
        material.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlineButton(
              onPressed:
                  _importing ? null : () => unawaited(_pickAndImportTheme()),
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
        const PreferencesHint(
          'Import VS Code theme JSON/JSONC (.colors subset). Changes apply immediately.',
        ),
      ],
    );
  }
}
