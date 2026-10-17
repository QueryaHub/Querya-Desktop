import 'dart:async' show unawaited;
import 'dart:convert';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/editor/querya_code_editor.dart';
import 'package:querya_desktop/core/editor/querya_code_language.dart';
import 'package:querya_desktop/features/workspace/xml_html_formatter.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';
import 'package:querya_desktop/core/ui/querya_control_tokens.dart';

/// Text of at least this many UTF-16 units (about 256 KB) is parsed, formatted
/// and minified on a worker isolate: `jsonDecode` and the XML formatter on a
/// multi-megabyte cell would hold the UI thread for whole frames.
@visibleForTesting
int inspectorIsolateThreshold = 256 * 1024;

String _prettyJson(String text) =>
    const JsonEncoder.withIndent('  ').convert(jsonDecode(text));

String _compactJson(String text) => jsonEncode(jsonDecode(text));

String _prettyXml(String text) => XmlHtmlFormatter.format(text);

bool _looksLikeJson(String trimmed) =>
    (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
    (trimmed.startsWith('[') && trimmed.endsWith(']'));

bool _looksLikeXml(String trimmed) =>
    trimmed.startsWith('<') && trimmed.endsWith('>');

/// Whether [trimmed] is valid JSON or valid XML (top-level so [compute] can run it).
({bool json, bool xml}) _detectKind(String trimmed) {
  if (_looksLikeJson(trimmed)) {
    try {
      jsonDecode(trimmed);
      return (json: true, xml: false);
    } catch (_) {
      return (json: false, xml: false);
    }
  }
  if (_looksLikeXml(trimmed)) {
    return (json: false, xml: XmlHtmlFormatter.validate(trimmed) == null);
  }
  return (json: false, xml: false);
}

/// Opens a rich modal inspector for viewing and editing large text, JSON, XML, or BLOB values.
///
/// **Apply** and **Ctrl/Cmd+Enter** return the edited string for local staging
/// (SQL grid). When [onSaveToDatabase] is set (Mongo field inspector), those
/// same actions persist through the callback — they are not a local-only
/// dismiss. **Cancel** still closes without writing.
Future<String?> showGridCellInspectorDialog({
  required material.BuildContext context,
  required String columnName,
  required String initialValue,
  int? rowIndex,
  String? dataTypeName,
  Future<void> Function(String value)? onSaveToDatabase,
}) {
  return showAppDialog<String>(
    context: context,
    builder: (ctx) => _GridCellInspectorDialog(
      columnName: columnName,
      initialValue: initialValue,
      rowIndex: rowIndex,
      dataTypeName: dataTypeName,
      onSaveToDatabase: onSaveToDatabase,
    ),
  );
}

class _GridCellInspectorDialog extends material.StatefulWidget {
  const _GridCellInspectorDialog({
    required this.columnName,
    required this.initialValue,
    this.rowIndex,
    this.dataTypeName,
    this.onSaveToDatabase,
  });

  final String columnName;
  final String initialValue;
  final int? rowIndex;
  final String? dataTypeName;
  final Future<void> Function(String value)? onSaveToDatabase;

  @override
  material.State<_GridCellInspectorDialog> createState() =>
      _GridCellInspectorDialogState();
}

class _GridCellInspectorDialogState
    extends material.State<_GridCellInspectorDialog> {
  late final material.TextEditingController _controller;
  bool _isNull = false;
  bool _wordWrap = true;
  bool _savingToDb = false;
  String? _saveError;

  QueryaCodeLanguage get _detectedLanguage {
    final t = _controller.text.trimLeft();
    if (t.startsWith('{') || t.startsWith('[')) {
      return QueryaCodeLanguage.json;
    }
    final upper = t.toUpperCase();
    if (upper.startsWith('SELECT ') ||
        upper.startsWith('INSERT ') ||
        upper.startsWith('UPDATE ') ||
        upper.startsWith('CREATE ') ||
        upper.startsWith('DELETE ') ||
        upper.startsWith('WITH ')) {
      return QueryaCodeLanguage.sql;
    }
    return QueryaCodeLanguage.plain;
  }

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

  bool _busy = false;

  /// Replaces the text with `transform(text)`; a text that does not parse is
  /// left as it is. Past [inspectorIsolateThreshold] the work runs on a worker
  /// isolate, with the buttons held back meanwhile; an edit made while it ran
  /// wins over the result.
  Future<void> _rewrite(String Function(String) transform) async {
    if (_busy) return;
    final text = _controller.text;
    String result;
    if (text.length < inspectorIsolateThreshold) {
      try {
        result = transform(text);
      } catch (_) {
        return;
      }
    } else {
      setState(() => _busy = true);
      try {
        result = await compute(transform, text);
      } catch (_) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      if (!mounted) return;
      _busy = false;
      if (!identical(text, _controller.text) && text != _controller.text) {
        setState(() {});
        return;
      }
    }
    setState(() {
      _isNull = false;
      _controller.text = result;
    });
  }

  void _formatJson() => unawaited(_rewrite(_prettyJson));

  void _minifyJson() => unawaited(_rewrite(_compactJson));

  void _formatXml() => unawaited(_rewrite(_prettyXml));

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

  // build() asks for both on every rebuild. Parsing a large cell each time
  // janks, so the answer is kept for the text it was computed for (the
  // controller hands out the same String until the text changes). Text past
  // [inspectorIsolateThreshold] is checked on a worker isolate: the buttons
  // appear when it answers.
  String? _kindText;
  var _kindIsJson = false;
  var _kindIsXml = false;
  var _detecting = false;

  void _refreshKind() {
    final raw = _controller.text;
    if (identical(raw, _kindText)) return;
    _kindText = raw;
    _kindIsJson = false;
    _kindIsXml = false;
    final text = raw.trim();
    if (!_looksLikeJson(text) && !_looksLikeXml(text)) return;
    if (raw.length >= inspectorIsolateThreshold) {
      _detectInBackground();
      return;
    }
    final kind = _detectKind(text);
    _kindIsJson = kind.json;
    _kindIsXml = kind.xml;
  }

  void _detectInBackground() {
    if (_detecting) return; // the running check re-reads the latest text
    final raw = _kindText;
    if (raw == null) return;
    _detecting = true;
    unawaited(compute(_detectKind, raw.trim()).then((kind) {
      _detecting = false;
      if (!mounted) return;
      if (identical(raw, _kindText)) {
        if (kind.json != _kindIsJson || kind.xml != _kindIsXml) {
          setState(() {
            _kindIsJson = kind.json;
            _kindIsXml = kind.xml;
          });
        }
      } else if (_kindText != null &&
          _kindText!.length >= inspectorIsolateThreshold) {
        _detectInBackground(); // edited meanwhile: check the new text
      }
    }, onError: (Object _) {
      _detecting = false;
    }));
  }

  bool _isJson() {
    _refreshKind();
    return _kindIsJson;
  }

  bool _isXml() {
    _refreshKind();
    return _kindIsXml;
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
    if (widget.onSaveToDatabase != null) {
      unawaited(_saveToDatabase());
      return;
    }
    final result = _isNull ? 'NULL' : _controller.text;
    material.Navigator.of(context).pop(result);
  }

  Future<void> _saveToDatabase() async {
    final save = widget.onSaveToDatabase;
    if (save == null || _savingToDb) return;
    setState(() {
      _savingToDb = true;
      _saveError = null;
    });
    try {
      await save(_isNull ? 'NULL' : _controller.text);
      if (!mounted) return;
      material.Navigator.of(context).pop(_isNull ? 'NULL' : _controller.text);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingToDb = false;
        _saveError = e.toString();
      });
    }
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
      child: QueryaDialogCard(
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
                    QueryaButton.ghost(
                      label: 'Format JSON',
                      icon: material.Icons.format_align_left_rounded,
                      loading: _busy,
                      onPressed: _busy ? null : _formatJson,
                      size: QueryaControlSize.sm,
                    ),
                    const Gap(6),
                    QueryaButton.ghost(
                      label: 'Minify',
                      icon: material.Icons.compress_rounded,
                      onPressed: _busy ? null : _minifyJson,
                      size: QueryaControlSize.sm,
                    ),
                    const Gap(6),
                  ],
                  if (_isXml()) ...[
                    QueryaButton.ghost(
                      label: 'Format XML',
                      icon: material.Icons.code_rounded,
                      loading: _busy,
                      onPressed: _busy ? null : _formatXml,
                      size: QueryaControlSize.sm,
                    ),
                    const Gap(6),
                  ],
                  QueryaButton.icon(
                    icon: material.Icons.close_rounded,
                    tooltip: 'Close',
                    size: QueryaControlSize.sm,
                    onPressed: () => material.Navigator.of(context).pop(null),
                  ),
                  if (_isHex()) ...[
                    QueryaButton.ghost(
                      label: 'Format Hex',
                      icon: material.Icons.grid_view_rounded,
                      onPressed: _formatHex,
                      size: QueryaControlSize.sm,
                    ),
                    const Gap(6),
                  ],
                  QueryaButton.ghost(
                    label: _wordWrap ? 'Wrap' : 'No Wrap',
                    icon: _wordWrap
                          ? material.Icons.wrap_text_rounded
                          : material.Icons.notes_rounded,
                    onPressed: () => setState(() => _wordWrap = !_wordWrap),
                    size: QueryaControlSize.sm,
                  ),
                  const Gap(6),
                  QueryaButton.ghost(
                    label: 'Set NULL',
                    onPressed: _isNull ? null : _setNull,
                    size: QueryaControlSize.sm,
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
                              QueryaButton.ghost(
                                label: 'Enter text value',
                                onPressed: () =>
                                    setState(() => _isNull = false),
                                size: QueryaControlSize.sm,
                              ),
                            ],
                          ),
                        )
                      : _wordWrap
                          ? QueryaCodeEditor(
                              controller: _controller,
                              language: _detectedLanguage,
                              autofocus: true,
                              fontSize: 12,
                              variant: QueryaCodeEditorVariant.material,
                              hintText: 'Enter cell value…',
                              contentPadding: const material.EdgeInsets.all(12),
                            )
                          : material.SingleChildScrollView(
                              scrollDirection: material.Axis.horizontal,
                              child: material.SizedBox(
                                width: 3000,
                                child: QueryaCodeEditor(
                                  controller: _controller,
                                  language: _detectedLanguage,
                                  autofocus: true,
                                  fontSize: 12,
                                  variant: QueryaCodeEditorVariant.material,
                                  hintText: 'Enter cell value…',
                                  contentPadding:
                                      const material.EdgeInsets.all(12),
                                ),
                              ),
                            ),
                ),
              ),
              const Gap(12),
              if (_saveError != null) ...[
                Text(_saveError!).small().muted(),
                const Gap(8),
              ],
              // Footer: two rows so Copy + metrics + extra Save to DB
              // actions fit the 420px dialog without overflowing.
              material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  material.Row(
                    children: [
                      QueryaButton.ghost(
                        label: 'Copy',
                        icon: material.Icons.copy_rounded,
                        onPressed: _savingToDb
                            ? null
                            : () {
                                Clipboard.setData(
                                  ClipboardData(
                                      text:
                                          _isNull ? 'NULL' : _controller.text),
                                );
                              },
                        size: QueryaControlSize.sm,
                      ),
                      const Gap(12),
                      if (!_isNull)
                        material.Expanded(
                          child: material.Text(
                            '$linesCount ${linesCount == 1 ? "line" : "lines"} · $charsCount chars · $bytesCount B',
                            overflow: material.TextOverflow.ellipsis,
                            style: material.TextStyle(
                              fontSize: 11,
                              color: cs.mutedForeground,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Gap(8),
                  material.Wrap(
                    alignment: material.WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      QueryaButton.ghost(
                        label: 'Cancel',
                        onPressed: _savingToDb
                            ? null
                            : () => material.Navigator.of(context).pop(null),
                        size: QueryaControlSize.sm,
                      ),
                      if (widget.onSaveToDatabase != null) ...[
                        QueryaButton.primary(
                          label: _savingToDb ? 'Saving…' : 'Save to DB',
                          icon: material.Icons.save_rounded,
                          loading: _savingToDb,
                          onPressed: _savingToDb ? null : _saveToDatabase,
                          size: QueryaControlSize.sm,
                        ),
                        QueryaButton.secondary(
                          label: 'Apply',
                          onPressed: _savingToDb ? null : _apply,
                          size: QueryaControlSize.sm,
                        ),
                      ] else
                        QueryaButton.primary(
                          label: 'Apply',
                          onPressed: _apply,
                          size: QueryaControlSize.sm,
                        ),
                    ],
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
