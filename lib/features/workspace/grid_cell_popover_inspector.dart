import 'dart:convert';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Opens a rich modal inspector for viewing and editing large text or JSON values.
Future<String?> showGridCellInspectorDialog({
  required material.BuildContext context,
  required String columnName,
  required String initialValue,
  int? rowIndex,
}) {
  return showAppDialog<String>(
    context: context,
    builder: (ctx) => _GridCellInspectorDialog(
      columnName: columnName,
      initialValue: initialValue,
      rowIndex: rowIndex,
    ),
  );
}

class _GridCellInspectorDialog extends material.StatefulWidget {
  const _GridCellInspectorDialog({
    required this.columnName,
    required this.initialValue,
    this.rowIndex,
  });

  final String columnName;
  final String initialValue;
  final int? rowIndex;

  @override
  material.State<_GridCellInspectorDialog> createState() =>
      _GridCellInspectorDialogState();
}

class _GridCellInspectorDialogState
    extends material.State<_GridCellInspectorDialog> {
  late final material.TextEditingController _controller;
  bool _isNull = false;

  @override
  void initState() {
    super.initState();
    _isNull = widget.initialValue == 'NULL';
    _controller = material.TextEditingController(
      text: _isNull ? '' : widget.initialValue,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _formatJson() {
    try {
      final parsed = jsonDecode(_controller.text);
      final pretty = const JsonEncoder.withIndent('  ').convert(parsed);
      setState(() {
        _isNull = false;
        _controller.text = pretty;
      });
    } catch (_) {
      // Not valid JSON, keep as is
    }
  }

  void _minifyJson() {
    try {
      final parsed = jsonDecode(_controller.text);
      final compact = jsonEncode(parsed);
      setState(() {
        _isNull = false;
        _controller.text = compact;
      });
    } catch (_) {
      // Not valid JSON, keep as is
    }
  }

  void _setNull() {
    setState(() {
      _isNull = true;
      _controller.clear();
    });
  }

  bool _isJson() {
    final text = _controller.text.trim();
    if ((text.startsWith('{') && text.endsWith('}')) ||
        (text.startsWith('[') && text.endsWith(']'))) {
      try {
        jsonDecode(text);
        return true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rowLabel =
        widget.rowIndex != null ? ' (Row ${widget.rowIndex! + 1})' : '';

    return material.Dialog(
      backgroundColor: cs.card,
      shape: material.RoundedRectangleBorder(
        borderRadius: material.BorderRadius.circular(8),
        side: material.BorderSide(color: cs.border, width: 1),
      ),
      child: material.ConstrainedBox(
        constraints: const material.BoxConstraints(
          minWidth: 500,
          maxWidth: 720,
          minHeight: 380,
          maxHeight: 560,
        ),
        child: material.Padding(
          padding: const material.EdgeInsets.all(16),
          child: material.Column(
            crossAxisAlignment: material.CrossAxisAlignment.stretch,
            children: [
              // Header
              material.Row(
                children: [
                  material.Icon(
                    material.Icons.data_object_rounded,
                    size: 18,
                    color: cs.primary,
                  ),
                  const Gap(8),
                  material.Expanded(
                    child: Text(
                      'Edit ${widget.columnName}$rowLabel',
                    ).semiBold(),
                  ),
                  if (_isJson()) ...[
                    GhostButton(
                      density: ButtonDensity.compact,
                      onPressed: _formatJson,
                      leading: const material.Icon(
                        material.Icons.format_align_left_rounded,
                        size: 14,
                      ),
                      child: const Text('Format JSON'),
                    ),
                    const Gap(6),
                    GhostButton(
                      density: ButtonDensity.compact,
                      onPressed: _minifyJson,
                      leading: const material.Icon(
                        material.Icons.compress_rounded,
                        size: 14,
                      ),
                      child: const Text('Minify'),
                    ),
                    const Gap(6),
                  ],
                  GhostButton(
                    density: ButtonDensity.compact,
                    onPressed: _isNull ? null : _setNull,
                    child: const Text('Set NULL'),
                  ),
                ],
              ),
              const Gap(12),

              // Editor Body
              material.Expanded(
                child: material.Container(
                  decoration: material.BoxDecoration(
                    color: cs.background,
                    borderRadius: material.BorderRadius.circular(6),
                    border: material.Border.all(
                      color: _isNull
                          ? cs.primary.withValues(alpha: 0.5)
                          : cs.border,
                      width: 1,
                    ),
                  ),
                  child: _isNull
                      ? material.Center(
                          child: material.Column(
                            mainAxisSize: material.MainAxisSize.min,
                            children: [
                              const Text('Value is NULL').muted().semiBold(),
                              const Gap(8),
                              GhostButton(
                                density: ButtonDensity.compact,
                                onPressed: () => setState(() => _isNull = false),
                                child: const Text('Enter text value'),
                              ),
                            ],
                          ),
                        )
                      : material.TextField(
                          controller: _controller,
                          maxLines: null,
                          expands: true,
                          autofocus: true,
                          style: const material.TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                          decoration: const material.InputDecoration(
                            border: material.InputBorder.none,
                            contentPadding: material.EdgeInsets.all(12),
                            hintText: 'Enter cell value…',
                          ),
                        ),
                ),
              ),
              const Gap(12),

              // Footer
              material.Row(
                children: [
                  GhostButton(
                    density: ButtonDensity.compact,
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: _isNull ? 'NULL' : _controller.text),
                      );
                    },
                    leading: const material.Icon(
                      material.Icons.copy_rounded,
                      size: 14,
                    ),
                    child: const Text('Copy'),
                  ),
                  const material.Spacer(),
                  OutlineButton(
                    density: ButtonDensity.compact,
                    onPressed: () => material.Navigator.of(context).pop(null),
                    child: const Text('Cancel'),
                  ),
                  const Gap(8),
                  PrimaryButton(
                    density: ButtonDensity.compact,
                    onPressed: () {
                      final result = _isNull ? 'NULL' : _controller.text;
                      material.Navigator.of(context).pop(result);
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
