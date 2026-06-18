import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/parser/color_parser.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_manifest.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:querya_desktop/core/theme/theme_editor_draft.dart';
import 'package:querya_desktop/core/theme/theme_editor_loader.dart';
import 'package:querya_desktop/features/settings/preferences_controls.dart';
import 'package:querya_desktop/features/settings/theme_color_picker_dialog.dart';
import 'package:querya_desktop/core/layout/ui_scale.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// MVP visual theme editor in Preferences → Appearance.
class ThemeEditorSection extends material.StatefulWidget {
  const ThemeEditorSection({super.key});

  @override
  material.State<ThemeEditorSection> createState() =>
      _ThemeEditorSectionState();
}

class _ThemeEditorSectionState extends material.State<ThemeEditorSection> {
  final _controller = ThemeController.instance;
  ThemeEditorDraft? _draft;
  bool _expanded = false;
  bool _loading = false;
  bool _exporting = false;
  String? _error;
  Timer? _previewDebounce;

  @override
  void dispose() {
    _previewDebounce?.cancel();
    unawaited(_controller.endEditorPreview());
    super.dispose();
  }

  Future<void> _loadDraft() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final draft = await ThemeEditorLoader.fromController(_controller);
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _loading = false;
      });
      if (_expanded) {
        unawaited(_controller.previewEditorManifest(draft.toManifest()));
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _toggleExpanded() async {
    final next = !_expanded;
    setState(() => _expanded = next);

    if (next) {
      if (_draft == null) {
        await _loadDraft();
      } else {
        unawaited(_controller.previewEditorManifest(_draft!.toManifest()));
      }
      return;
    }

    await _controller.endEditorPreview();
  }

  void _schedulePreview() {
    final draft = _draft;
    if (draft == null) return;

    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted || _draft == null) return;
      unawaited(_controller.previewEditorManifest(_draft!.toManifest()));
    });
  }

  Future<void> _pickColor(ThemeEditorColorField field) async {
    final draft = _draft;
    if (draft == null) return;

    final currentHex = draft.colorHex(field);
    Color initial;
    try {
      initial = currentHex != null
          ? parseQueryaThemeColor(currentHex)
          : Theme.of(context).colorScheme.primary;
    } on FormatException {
      initial = Theme.of(context).colorScheme.primary;
    }

    final picked = await showThemeColorPickerDialog(
      context: context,
      initial: initial,
    );
    if (picked == null || !mounted) return;

    setState(() {
      draft.setColor(field, picked);
    });
    _schedulePreview();
  }

  Future<void> _exportDraft() async {
    final draft = _draft;
    if (draft == null) return;

    setState(() {
      _exporting = true;
      _error = null;
    });

    try {
      final exportDraft = draft.forExport();
      final location = await getSaveLocation(
        suggestedName: '${exportDraft.id}.json',
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Querya theme',
            extensions: ['json'],
          ),
        ],
      );
      if (location == null) return;

      await File(location.path).writeAsString(exportDraft.toExportJsonString());
      QueryaThemeManifest.fromJsonString(exportDraft.toExportJsonString());
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      children: [
        const material.SizedBox(height: 12),
        material.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlineButton(
              onPressed: _loading ? null : () => unawaited(_toggleExpanded()),
              child: material.Text(
                _loading
                    ? 'Loading editor…'
                    : _expanded
                        ? 'Hide theme editor'
                        : 'Edit theme colors…',
              ),
            ),
            if (_expanded && _draft != null)
              OutlineButton(
                onPressed: _exporting ? null : () => unawaited(_exportDraft()),
                child: material.Text(
                  _exporting ? 'Exporting…' : 'Export theme…',
                ),
              ),
            if (_expanded)
              OutlineButton(
                onPressed: _loading ? null : () => unawaited(_loadDraft()),
                child: const material.Text('Reset from current'),
              ),
          ],
        ),
        if (_expanded && _draft?.readOnlySource == true) ...[
          const material.SizedBox(height: 8),
          const PreferencesHint(
            'Built-in themes are not modified in place. Export saves a copy '
            'with a new id that you can import into the themes folder.',
          ),
        ],
        if (_error != null) ...[
          const material.SizedBox(height: 8),
          material.Text(
            _error!,
            style: material.TextStyle(fontSize: 12, color: cs.destructive),
          ),
        ],
        if (_expanded && _draft != null) ...[
          const material.SizedBox(height: 12),
          for (final field in themeEditorMvpColorFields)
            _ThemeEditorColorRow(
              field: field,
              hex: _draft!.colorHex(field),
              onPick: () => unawaited(_pickColor(field)),
            ),
        ],
      ],
    );
  }
}

class _ThemeEditorColorRow extends material.StatelessWidget {
  const _ThemeEditorColorRow({
    required this.field,
    required this.hex,
    required this.onPick,
  });

  final ThemeEditorColorField field;
  final String? hex;
  final material.VoidCallback onPick;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color? swatchColor;
    if (hex != null) {
      try {
        swatchColor = parseQueryaThemeColor(hex!);
      } on FormatException {
        swatchColor = null;
      }
    }

    return material.Padding(
      padding: const material.EdgeInsets.only(bottom: 8),
      child: material.Row(
        children: [
          material.SizedBox(
            width: context.scaled(kPreferencesLabelWidth),
            child: material.Text(
              field.label,
              style: material.TextStyle(
                fontSize: 13,
                color: cs.popoverForeground,
              ),
            ),
          ),
          const material.SizedBox(width: 12),
          material.InkWell(
            onTap: onPick,
            borderRadius: material.BorderRadius.circular(6),
            child: material.Container(
              width: 28,
              height: 28,
              decoration: material.BoxDecoration(
                color: swatchColor ?? cs.muted,
                borderRadius: material.BorderRadius.circular(6),
                border: material.Border.all(color: cs.border),
              ),
            ),
          ),
          const material.SizedBox(width: 10),
          material.Expanded(
            child: material.Text(
              hex ?? '—',
              style: material.TextStyle(
                fontSize: 12,
                color: cs.mutedForeground,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
