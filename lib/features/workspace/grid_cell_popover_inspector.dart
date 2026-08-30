import 'dart:convert';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/features/workspace/xml_html_formatter.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Opens a rich modal inspector for viewing and editing large text, JSON, XML, or BLOB values.
Future<String?> showGridCellInspectorDialog({
  required material.BuildContext context,
  required String columnName,
  required String initialValue,
  int? rowIndex,
  String? dataTypeName,
}) {
  return showAppDialog<String>(
    context: context,
    builder: (ctx) => _GridCellInspectorDialog(
      columnName: columnName,
      initialValue: initialValue,
      rowIndex: rowIndex,
      dataTypeName: dataTypeName,
    ),
  );
}

class _GridCellInspectorDialog extends material.StatefulWidget {
  const _GridCellInspectorDialog({
    required this.columnName,
    required this.initialValue,
    this.rowIndex,
    this.dataTypeName,
  });

  final String columnName;
  final String initialValue;
  final int? rowIndex;
  final String? dataTypeName;

  @override
  material.State<_GridCellInspectorDialog> createState() =>
      _GridCellInspectorDialogState();
}

class _GridCellInspectorDialogState
    extends material.State<_GridCellInspectorDialog> {
  late final material.TextEditingController _controller;
  bool _isNull = false;
  bool _wordWrap = true;

  @override
  void initState() {
    super.initState();
    _isNull = widget.initialValue == 'NULL';
    _controller = material.TextEditingController(
      text: _isNull ? '' : widget.initialValue,
    );
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
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

  void _formatXml() {
    try {
      final pretty = XmlHtmlFormatter.format(_controller.text);
      setState(() {
        _isNull = false;
        _controller.text = pretty;
      });
    } catch (_) {}
  }

  void _formatHex() {
    var raw = _controller.text.trim();
    var prefix = '';
    if (raw.startsWith(r'\x') || raw.startsWith(r'\X')) {
      prefix = r'\x';
      raw = raw.substring(2);
    } else if (raw.startsWith('0x') || raw.startsWith('0X')) {
      prefix = '0x';
      raw = raw.substring(2);
    }
    final clean = raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (clean.isEmpty) return;

    final pairs = <String>[];
    for (var i = 0; i < clean.length; i += 2) {
      final end = (i + 2 <= clean.length) ? i + 2 : clean.length;
      pairs.add(clean.substring(i, end));
    }
    final formatted =
        prefix.isNotEmpty ? '$prefix ${pairs.join(' ')}' : pairs.join(' ');
    setState(() {
      _isNull = false;
      _controller.text = formatted;
    });
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

  bool _isXml() {
    final text = _controller.text.trim();
    if (text.startsWith('<') && text.endsWith('>')) {
      return XmlHtmlFormatter.validate(text) == null;
    }
    return false;
  }

  bool _isHex() {
    final text = _controller.text.trim();
    if (text.length < 4) return false;
    var hex = text;
    if (hex.startsWith(r'\x') ||
        hex.startsWith(r'\X') ||
        hex.startsWith('0x') ||
        hex.startsWith('0X')) {
      hex = hex.substring(2);
    }
    final clean = hex.replaceAll(RegExp(r'\s+'), '');
    return clean.isNotEmpty &&
        clean.length.isEven &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean);
  }

  void _apply() {
    final result = _isNull ? 'NULL' : _controller.text;
    material.Navigator.of(context).pop(result);
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rowLabel =
        widget.rowIndex != null ? ' (Row ${widget.rowIndex! + 1})' : '';
    final text = _isNull ? '' : _controller.text;
    final linesCount = text.isEmpty ? 0 : '\n'.allMatches(text).length + 1;
    final charsCount = text.length;
    final bytesCount = utf8.encode(text).length;

    return material.CallbackShortcuts(
      bindings: {
        const material.SingleActivator(
          LogicalKeyboardKey.enter,
          control: true,
        ): _apply,
        const material.SingleActivator(
          LogicalKeyboardKey.enter,
          meta: true,
        ): _apply,
        const material.SingleActivator(
          LogicalKeyboardKey.numpadEnter,
          control: true,
        ): _apply,
        const material.SingleActivator(
          LogicalKeyboardKey.numpadEnter,
          meta: true,
        ): _apply,
        const material.SingleActivator(
          LogicalKeyboardKey.keyN,
          alt: true,
        ): _setNull,
      },
      child: material.Dialog(
        backgroundColor: cs.card,
        shape: material.RoundedRectangleBorder(
          borderRadius: material.BorderRadius.circular(8),
          side: material.BorderSide(color: cs.border, width: 1),
        ),
        child: material.ConstrainedBox(
          constraints: const material.BoxConstraints(
            minWidth: 520,
            maxWidth: 760,
            minHeight: 400,
            maxHeight: 580,
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
                    if (_isXml()) ...[
                      GhostButton(
                        density: ButtonDensity.compact,
                        onPressed: _formatXml,
                        leading: const material.Icon(
                          material.Icons.code_rounded,
                          size: 14,
                        ),
                        child: const Text('Format XML'),
                      ),
                      const Gap(6),
                    ],
                    if (_isHex()) ...[
                      GhostButton(
                        density: ButtonDensity.compact,
                        onPressed: _formatHex,
                        leading: const material.Icon(
                          material.Icons.grid_view_rounded,
                          size: 14,
                        ),
                        child: const Text('Format Hex'),
                      ),
                      const Gap(6),
                    ],
                    GhostButton(
                      density: ButtonDensity.compact,
                      onPressed: () => setState(() => _wordWrap = !_wordWrap),
                      leading: material.Icon(
                        _wordWrap
                            ? material.Icons.wrap_text_rounded
                            : material.Icons.notes_rounded,
                        size: 14,
                      ),
                      child: Text(_wordWrap ? 'Wrap' : 'No Wrap'),
                    ),
                    const Gap(6),
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
                                  onPressed: () =>
                                      setState(() => _isNull = false),
                                  child: const Text('Enter text value'),
                                ),
                              ],
                            ),
                          )
                        : _wordWrap
                            ? material.TextField(
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
                              )
                            : material.SingleChildScrollView(
                                scrollDirection: material.Axis.horizontal,
                                child: material.SingleChildScrollView(
                                  scrollDirection: material.Axis.vertical,
                                  child: material.SizedBox(
                                    width: 3000,
                                    child: material.TextField(
                                      controller: _controller,
                                      maxLines: null,
                                      autofocus: true,
                                      style: const material.TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                      ),
                                      decoration: const material.InputDecoration(
                                        border: material.InputBorder.none,
                                        contentPadding:
                                            material.EdgeInsets.all(12),
                                        hintText: 'Enter cell value…',
                                      ),
                                    ),
                                  ),
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
                          ClipboardData(
                              text: _isNull ? 'NULL' : _controller.text),
                        );
                      },
                      leading: const material.Icon(
                        material.Icons.copy_rounded,
                        size: 14,
                      ),
                      child: const Text('Copy'),
                    ),
                    const Gap(12),
                    if (!_isNull)
                      material.Text(
                        '$linesCount ${linesCount == 1 ? "line" : "lines"} · $charsCount chars · $bytesCount B',
                        style: material.TextStyle(
                          fontSize: 11,
                          color: cs.mutedForeground,
                        ),
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
                      onPressed: _apply,
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
