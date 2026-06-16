import 'dart:async' show unawaited;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/motion/querya_motion_controller.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
import 'package:querya_desktop/core/platform/open_directory.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:querya_desktop/core/theme/theme_import_service.dart';
import 'package:querya_desktop/core/theme/theme_load_result.dart';
import 'package:querya_desktop/core/theme/theme_paths.dart';
import 'package:querya_desktop/features/settings/preferences_controls.dart';
import 'package:querya_desktop/features/settings/theme_editor_section.dart';
import 'package:querya_desktop/features/settings/theme_picker_button.dart';
import 'package:querya_desktop/features/settings/theme_preview_card.dart';
import 'package:querya_desktop/features/settings/theme_remote_install_dialog.dart';
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
  String? _importError;
  String? _folderOpenError;
  bool _importing = false;
  bool _installingFromUrl = false;
  bool _openingThemesFolder = false;

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

  Future<void> _setThemeById(String id) async {
    await _controller.setThemeById(id);
  }

  Future<ThemePreviewResult> _previewThemeById(String id) async {
    final result = await _controller.previewThemeById(id);
    return switch (result) {
      ThemeLoadSuccess(:final theme) => ThemePreviewResult.theme(theme),
      ThemeLoadFailure(:final message) => ThemePreviewResult.error(message),
    };
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
      final result = await _controller.importRegistryThemeFile(path);
      if (!mounted) return;
      switch (result) {
        case ThemeDefinitionImportSuccess():
          setState(() => _importError = null);
        case ThemeDefinitionImportFailure(:final message):
          setState(() => _importError = message);
      }
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  Future<void> _installThemeFromUrl() async {
    final request = await showThemeRemoteInstallDialog(context);
    if (request == null) return;

    setState(() {
      _installingFromUrl = true;
      _importError = null;
    });
    try {
      final result = await _controller.importRegistryThemeFromUrl(
        request.url,
        sha256Checksum: request.sha256Checksum,
      );
      if (!mounted) return;
      switch (result) {
        case ThemeDefinitionImportSuccess():
          setState(() => _importError = null);
        case ThemeDefinitionImportFailure(:final message):
          setState(() => _importError = message);
      }
    } finally {
      if (mounted) {
        setState(() => _installingFromUrl = false);
      }
    }
  }

  Future<void> _resetAppearance() async {
    await _controller.resetToDefaults();
    if (mounted) setState(() => _importError = null);
  }

  Future<void> _refreshThemes() async {
    await _controller.loadAvailableThemes();
  }

  Future<void> _openThemesFolder() async {
    setState(() {
      _openingThemesFolder = true;
      _folderOpenError = null;
    });
    try {
      final dir = await ThemePaths.ensureUserThemesDirectory();
      final opened = await openDirectoryInFileManager(dir.path);
      if (!mounted) return;
      if (!opened) {
        setState(() => _folderOpenError = 'Could not open themes folder.');
      }
    } finally {
      if (mounted) {
        setState(() => _openingThemesFolder = false);
      }
    }
  }

  Future<void> _setThemeAnimation(bool enabled) async {
    await _controller.setThemeAnimationEnabled(enabled);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final c = _controller;
    final themes = c.availableThemes;
    final refreshingThemes = c.isLoadingAvailableThemes;

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
          label: 'Theme',
          control: ThemePickerButton(
            themes: themes,
            selectedThemeId: c.effectiveSelectedThemeId,
            expandToParent: true,
            isLoading: refreshingThemes,
            onSelected: (id) => unawaited(_setThemeById(id)),
            onPreviewTheme: _previewThemeById,
          ),
        ),
        if (c.selectedThemeLoadError != null) ...[
          const material.SizedBox(height: 8),
          material.Padding(
            padding: const material.EdgeInsets.only(
              left: kPreferencesLabelWidth + 12,
            ),
            child: material.Text(
              c.selectedThemeLoadError!,
              style: material.TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.destructive,
              ),
            ),
          ),
        ],
        const material.SizedBox(height: 8),
        const material.Padding(
          padding: material.EdgeInsets.only(left: kPreferencesLabelWidth + 12),
          child: PreferencesHint(
            'Themes are loaded from the app support themes folder. '
            'Drop .json or .jsonc files there; the folder is watched automatically '
            'or use Refresh themes.',
          ),
        ),
        const ThemeEditorSection(),
        const material.SizedBox(height: 12),
        const PreferencesFieldRow(
          label: 'Interface scale',
          hint:
              'Snap to presets (75%, 85%, 90%, 100% …). Hold Shift for 1% fine control.',
          control: InterfaceScaleSlider(),
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
        PreferencesFieldRow(
          label: 'Motion',
          control: material.ListenableBuilder(
            listenable: QueryaMotionController.instance,
            builder: (context, _) {
              final controller = QueryaMotionController.instance;
              return PreferencesDropdownMenu<QueryaMotionLevel>(
                value: controller.level,
                onSelected: (v) {
                  if (v != null) unawaited(controller.setLevel(v));
                },
                entries: const [
                  material.DropdownMenuEntry(
                    value: QueryaMotionLevel.full,
                    label: 'Full',
                  ),
                  material.DropdownMenuEntry(
                    value: QueryaMotionLevel.reduced,
                    label: 'Reduced',
                  ),
                  material.DropdownMenuEntry(
                    value: QueryaMotionLevel.off,
                    label: 'Off',
                  ),
                ],
              );
            },
          ),
        ),
        const material.SizedBox(height: 4),
        const PreferencesHint(
          'Full enables all animations. Reduced cuts durations in half. Off disables all transitions.',
        ),
        const material.SizedBox(height: 12),
        material.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlineButton(
              onPressed: (_importing || _installingFromUrl)
                  ? null
                  : () => unawaited(_pickAndImportTheme()),
              child: material.Text(_importing ? 'Importing…' : 'Import theme…'),
            ),
            OutlineButton(
              onPressed: (_importing || _installingFromUrl || refreshingThemes)
                  ? null
                  : () => unawaited(_installThemeFromUrl()),
              child: material.Text(
                _installingFromUrl ? 'Installing…' : 'Install from URL…',
              ),
            ),
            OutlineButton(
              onPressed: (_importing || _installingFromUrl || refreshingThemes)
                  ? null
                  : () => unawaited(_refreshThemes()),
              child: material.Text(
                refreshingThemes ? 'Refreshing…' : 'Refresh themes',
              ),
            ),
            OutlineButton(
              onPressed:
                  (_importing || _installingFromUrl || _openingThemesFolder)
                      ? null
                      : () => unawaited(_openThemesFolder()),
              child: material.Text(
                _openingThemesFolder ? 'Opening…' : 'Open themes folder',
              ),
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
        if (_folderOpenError != null) ...[
          const material.SizedBox(height: 8),
          material.Text(
            _folderOpenError!,
            style: material.TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.destructive,
            ),
          ),
        ],
        const material.SizedBox(height: 4),
        const PreferencesHint(
          'Import copies a theme into the themes folder. '
          'Install from URL requires HTTPS and optional SHA-256 verification. '
          'VS Code JSON/JSONC (.colors subset) and Querya custom JSON are supported.',
        ),
      ],
    );
  }
}
