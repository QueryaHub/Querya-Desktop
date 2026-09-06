import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/theme/parser/color_parser.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_manifest.dart';
import 'package:querya_desktop/core/theme/querya_typography.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:querya_desktop/core/theme/theme_editor_draft.dart';
import 'package:querya_desktop/core/theme/theme_editor_loader.dart';
import 'package:querya_desktop/features/settings/theme_color_picker_dialog.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Shows the focused Theme Studio modal dialog with live token editing and real-time preview.
Future<void> showThemeEditorDialog(material.BuildContext context) {
  return showAppDialog<void>(
    context: context,
    builder: (dialogContext) => const ThemeEditorDialog(),
  );
}

/// Focused Theme Studio modal for editing palette tokens and exporting custom themes.
class ThemeEditorDialog extends material.StatefulWidget {
  const ThemeEditorDialog({super.key});

  @override
  material.State<ThemeEditorDialog> createState() => _ThemeEditorDialogState();
}

class _ThemeEditorDialogState extends material.State<ThemeEditorDialog> {
  final _controller = ThemeController.instance;
  ThemeEditorDraft? _draft;
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  Timer? _previewDebounce;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDraft());
  }

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
      unawaited(_controller.previewEditorManifest(draft.toManifest()));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return material.AlertDialog(
      backgroundColor: cs.popover,
      shape: material.RoundedRectangleBorder(
        borderRadius: material.BorderRadius.circular(12),
        side: material.BorderSide(color: cs.border.withValues(alpha: 0.35)),
      ),
      titlePadding: const material.EdgeInsets.fromLTRB(20, 16, 16, 12),
      contentPadding: const material.EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const material.EdgeInsets.fromLTRB(20, 12, 20, 16),
      title: material.Row(
        children: [
          material.Icon(
            material.Icons.palette_outlined,
            size: 20,
            color: cs.primary,
          ),
          const material.SizedBox(width: 10),
          material.Expanded(
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              children: [
                const Text('Theme Studio')
                    .semiBold()
                    .medium()
                    .foreground(),
                const material.SizedBox(height: 2),
                const Text(
                  'Customize color tokens with real-time UI preview',
                ).muted().xSmall(),
              ],
            ),
          ),
          IconButton.ghost(
            icon: const material.Icon(material.Icons.close, size: 16),
            onPressed: () => material.Navigator.of(context).pop(),
            density: ButtonDensity.compact,
          ),
        ],
      ),
      content: material.SizedBox(
        width: 540,
        height: 480,
        child: _loading
            ? const material.Center(
                child: material.CircularProgressIndicator(),
              )
            : material.SingleChildScrollView(
                child: material.Column(
                  crossAxisAlignment: material.CrossAxisAlignment.start,
                  children: [
                    if (_draft != null) ...[
                      // Info Pill
                      material.Container(
                        padding: const material.EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: material.BoxDecoration(
                          color: cs.muted.withValues(alpha: 0.25),
                          borderRadius: material.BorderRadius.circular(6),
                          border: material.Border.all(
                            color: cs.border.withValues(alpha: 0.2),
                          ),
                        ),
                        child: material.Row(
                          children: [
                            material.Icon(
                              material.Icons.info_outline,
                              size: 14,
                              color: cs.mutedForeground,
                            ),
                            const material.SizedBox(width: 8),
                            material.Expanded(
                              child: material.Text(
                                _draft!.readOnlySource
                                    ? 'Editing copy of built-in theme "${_draft!.name}". Export to save.'
                                    : 'Editing theme "${_draft!.name}". Changes preview live.',
                                style: material.TextStyle(
                                  fontSize: 12,
                                  color: cs.mutedForeground,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const material.SizedBox(height: 14),
                    ],

                    if (_error != null) ...[
                      material.Padding(
                        padding: const material.EdgeInsets.only(bottom: 12),
                        child: material.Text(
                          _error!,
                          style: material.TextStyle(
                            fontSize: 12,
                            color: cs.destructive,
                          ),
                        ),
                      ),
                    ],

                    if (_draft != null) ...[
                      material.Container(
                        decoration: material.BoxDecoration(
                          color: cs.muted.withValues(alpha: 0.1),
                          borderRadius: material.BorderRadius.circular(8),
                          border: material.Border.all(
                            color: cs.border.withValues(alpha: 0.2),
                          ),
                        ),
                        child: material.Column(
                          children: [
                            for (var i = 0;
                                i < themeEditorMvpColorFields.length;
                                i++) ...[
                              if (i > 0)
                                Divider(
                                  height: 1,
                                  color: cs.border.withValues(alpha: 0.18),
                                ),
                              _ThemeEditorColorRow(
                                field: themeEditorMvpColorFields[i],
                                hex: _draft!.colorHex(
                                  themeEditorMvpColorFields[i],
                                ),
                                onPick: () => unawaited(
                                  _pickColor(themeEditorMvpColorFields[i]),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        OutlineButton(
          onPressed: _loading ? null : () => unawaited(_loadDraft()),
          child: const material.Text('Reset from current'),
        ),
        if (_draft != null)
          OutlineButton(
            onPressed: _exporting ? null : () => unawaited(_exportDraft()),
            child: material.Text(
              _exporting ? 'Exporting…' : 'Export theme…',
            ),
          ),
        PrimaryButton(
          onPressed: () => material.Navigator.of(context).pop(),
          child: const material.Text('Done'),
        ),
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
      padding: const material.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: material.Row(
        children: [
          material.Expanded(
            child: material.Text(
              field.label,
              style: material.TextStyle(
                fontSize: 13,
                color: cs.foreground,
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
                border: material.Border.all(
                  color: cs.border.withValues(alpha: 0.5),
                ),
                boxShadow: [
                  material.BoxShadow(
                    color: material.Colors.black.withValues(alpha: 0.06),
                    offset: const material.Offset(0, 1),
                    blurRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          const material.SizedBox(width: 10),
          material.SizedBox(
            width: 80,
            child: material.Text(
              hex ?? '—',
              style: material.TextStyle(
                fontSize: 12,
                color: cs.mutedForeground,
                fontFamily: QueryaTypography.mono,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
